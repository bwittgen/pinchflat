defmodule Pinchflat.Plex.PlexApi do
  @moduledoc """
  Methods for interacting with the Plex Media Server API.

  Supports triggering library scans, matching downloaded media to Plex
  library items, detecting metadata mismatches, and syncing watch status.
  """

  require Logger

  alias Pinchflat.Settings
  alias Pinchflat.Media.MediaItem
  alias Pinchflat.Plex.PlexBehaviour

  @behaviour PlexBehaviour

  @doc """
  Determines if the Plex integration is enabled by checking
  if both the server URL and token are configured.

  Returns boolean()
  """
  @impl PlexBehaviour
  def enabled? do
    server_url = Settings.get!(:plex_server_url)
    token = Settings.get!(:plex_token)

    is_binary(server_url) && server_url != "" &&
      is_binary(token) && token != ""
  end

  @doc """
  Triggers a Plex library scan. If a section_id is provided, only that
  library section is scanned. Otherwise, all sections are scanned.

  Returns :ok | {:error, binary()}
  """
  @impl PlexBehaviour
  def trigger_library_scan(section_id \\ nil) do
    if section_id do
      scan_section(section_id)
    else
      scan_all_sections()
    end
  end

  @doc """
  Attempts to find a downloaded media item in the Plex library by
  searching for its file path across all library sections.

  Returns {:ok, map()} | {:error, binary()}
  """
  @impl PlexBehaviour
  def find_media_item(%MediaItem{} = media_item) do
    filepath = media_item.media_filepath

    if is_nil(filepath) || filepath == "" do
      {:error, "Media item has no file path"}
    else
      case get_library_sections() do
        {:ok, sections} ->
          search_sections_for_file(sections, filepath, media_item)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Compares metadata between Pinchflat and Plex for a given media item.
  Returns a list of detected mismatches.

  Returns {:ok, [map()]} | {:error, binary()}
  """
  @impl PlexBehaviour
  def check_metadata(%MediaItem{} = media_item, plex_item) do
    mismatches =
      []
      |> check_field("title", media_item.title, Map.get(plex_item, "title"))
      |> check_field("year", get_year(media_item), Map.get(plex_item, "year"))
      |> check_field("duration", media_item.duration_seconds, get_plex_duration_seconds(plex_item))

    {:ok, mismatches}
  end

  @doc """
  Retrieves the watch status of a media item from Plex.

  Returns {:ok, map()} | {:error, binary()}
  """
  @impl PlexBehaviour
  def sync_watch_status(%MediaItem{} = _media_item, plex_item) do
    rating_key = Map.get(plex_item, "ratingKey")

    if is_nil(rating_key) do
      {:error, "Plex item has no rating key"}
    else
      url = build_url("/library/metadata/#{rating_key}")

      case http_client().get(url, auth_headers()) do
        {:ok, body} ->
          parse_watch_status(body)

        {:error, reason} ->
          {:error, "Failed to get watch status: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Tests connectivity to the Plex server.

  Returns :ok | {:error, binary()}
  """
  def test_connection do
    url = build_url("/")

    case http_client().get(url, auth_headers()) do
      {:ok, body} ->
        case Phoenix.json_library().decode(body) do
          {:ok, %{"MediaContainer" => _}} -> :ok
          {:ok, _} -> :ok
          {:error, _} -> :ok
        end

      {:error, reason} ->
        {:error, "Failed to connect to Plex server: #{inspect(reason)}"}
    end
  end

  # Private functions

  defp scan_section(section_id) do
    url = build_url("/library/sections/#{section_id}/refresh")

    case http_client().get(url, auth_headers()) do
      {:ok, _} ->
        Logger.info("Triggered Plex library scan for section #{section_id}")
        :ok

      {:error, reason} ->
        {:error, "Failed to trigger Plex scan for section #{section_id}: #{inspect(reason)}"}
    end
  end

  defp scan_all_sections do
    case get_library_sections() do
      {:ok, sections} ->
        Enum.each(sections, fn section ->
          section_id = Map.get(section, "key")

          if section_id do
            scan_section(section_id)
          end
        end)

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_library_sections do
    url = build_url("/library/sections")

    case http_client().get(url, auth_headers()) do
      {:ok, body} ->
        parse_sections(body)

      {:error, reason} ->
        {:error, "Failed to get Plex library sections: #{inspect(reason)}"}
    end
  end

  defp parse_sections(body) do
    case Phoenix.json_library().decode(body) do
      {:ok, %{"MediaContainer" => %{"Directory" => directories}}} when is_list(directories) ->
        {:ok, directories}

      {:ok, %{"MediaContainer" => _}} ->
        {:ok, []}

      {:ok, _} ->
        {:error, "Unexpected Plex API response format"}

      {:error, _} ->
        {:error, "Failed to parse Plex API response"}
    end
  end

  defp search_sections_for_file(sections, filepath, media_item) do
    Enum.reduce_while(sections, {:error, "Media not found in Plex"}, fn section, acc ->
      section_id = Map.get(section, "key")

      if section_id do
        case search_section_for_file(section_id, filepath, media_item) do
          {:ok, item} -> {:halt, {:ok, item}}
          {:error, _} -> {:cont, acc}
        end
      else
        {:cont, acc}
      end
    end)
  end

  defp search_section_for_file(section_id, filepath, media_item) do
    title = media_item.title || ""
    encoded_title = URI.encode(title)
    url = build_url("/library/sections/#{section_id}/search?type=4&query=#{encoded_title}")

    case http_client().get(url, auth_headers()) do
      {:ok, body} ->
        parse_search_results(body, media_item, filepath)

      {:error, _reason} ->
        {:error, "Search failed for section #{section_id}"}
    end
  end

  defp parse_search_results(body, media_item, filepath) do
    case Phoenix.json_library().decode(body) do
      {:ok, %{"MediaContainer" => %{"Metadata" => metadata}}} when is_list(metadata) ->
        match =
          Enum.find(metadata, fn item ->
            matches_by_filepath?(item, filepath) || matches_media_item?(item, media_item)
          end)

        if match do
          {:ok, match}
        else
          {:error, "No matching item found in search results"}
        end

      {:ok, _} ->
        {:error, "No results found"}

      {:error, _} ->
        {:error, "Failed to parse search results"}
    end
  end

  defp matches_by_filepath?(plex_item, filepath) do
    plex_item
    |> Map.get("Media", [])
    |> Enum.any?(fn media ->
      media
      |> Map.get("Part", [])
      |> Enum.any?(fn part ->
        Map.get(part, "file") == filepath
      end)
    end)
  end

  defp matches_media_item?(plex_item, media_item) do
    plex_title = Map.get(plex_item, "title", "")
    media_title = media_item.title || ""

    String.downcase(plex_title) == String.downcase(media_title)
  end

  defp check_field(mismatches, _field, nil, _plex_value), do: mismatches
  defp check_field(mismatches, _field, _pinchflat_value, nil), do: mismatches

  defp check_field(mismatches, field, pinchflat_value, plex_value) do
    if values_match?(pinchflat_value, plex_value) do
      mismatches
    else
      [%{field: field, pinchflat_value: pinchflat_value, plex_value: plex_value} | mismatches]
    end
  end

  defp values_match?(a, b) when is_binary(a) and is_binary(b) do
    String.downcase(String.trim(a)) == String.downcase(String.trim(b))
  end

  defp values_match?(a, b) when is_integer(a) and is_integer(b) do
    # Allow 5-second tolerance for duration comparisons
    abs(a - b) <= 5
  end

  defp values_match?(a, b), do: a == b

  defp get_year(%MediaItem{uploaded_at: nil}), do: nil

  defp get_year(%MediaItem{uploaded_at: uploaded_at}) do
    uploaded_at.year
  end

  defp get_plex_duration_seconds(plex_item) do
    case Map.get(plex_item, "duration") do
      nil -> nil
      duration when is_integer(duration) -> div(duration, 1000)
      _ -> nil
    end
  end

  defp parse_watch_status(body) do
    case Phoenix.json_library().decode(body) do
      {:ok, %{"MediaContainer" => %{"Metadata" => [item | _]}}} ->
        {:ok,
         %{
           watched: Map.get(item, "viewCount", 0) > 0,
           view_count: Map.get(item, "viewCount", 0),
           last_viewed_at: Map.get(item, "lastViewedAt")
         }}

      {:ok, _} ->
        {:error, "Could not parse watch status"}

      {:error, _} ->
        {:error, "Failed to parse Plex response"}
    end
  end

  defp build_url(path) do
    server_url =
      Settings.get!(:plex_server_url)
      |> String.trim_trailing("/")

    "#{server_url}#{path}"
  end

  defp auth_headers do
    token = Settings.get!(:plex_token)
    [{"X-Plex-Token", token}, {"Accept", "application/json"}]
  end

  defp http_client do
    Application.get_env(:pinchflat, :http_client, Pinchflat.HTTP.HTTPClient)
  end
end
