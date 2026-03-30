defmodule Pinchflat.Plex.PlexScanWorker do
  @moduledoc """
  Oban worker that triggers Plex library scans after downloads complete.

  After triggering a scan, schedules a PlexLookupWorker job with a delay
  to give Plex time to index the newly downloaded file before attempting
  to look it up.
  """

  use Oban.Worker,
    queue: :local_data,
    priority: 3,
    max_attempts: 3,
    tags: ["plex", "library_scan"]

  require Logger

  alias Pinchflat.Plex.PlexApi
  alias Pinchflat.Plex.PlexLookupWorker

  @default_lookup_delay_seconds 30

  @doc """
  Enqueues a Plex scan job for a given media item.

  Returns {:ok, %Oban.Job{}} | {:error, term()}
  """
  def enqueue_for_media_item(%{id: media_item_id}) do
    %{media_item_id: media_item_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"media_item_id" => media_item_id}}) do
    plex_api = plex_runner()

    if plex_api.enabled?() do
      Logger.info("Triggering Plex library scan for media item #{media_item_id}")

      case plex_api.trigger_library_scan() do
        :ok ->
          enqueue_lookup(media_item_id)
          :ok

        {:error, reason} ->
          Logger.warning("Plex scan failed for media item #{media_item_id}: #{inspect(reason)}")
          :ok
      end
    else
      Logger.debug("Plex integration not enabled, skipping scan for media item #{media_item_id}")
      :ok
    end
  end

  defp enqueue_lookup(media_item_id) do
    delay = lookup_delay_seconds()

    Logger.info(
      "Scheduling Plex lookup for media item #{media_item_id} in #{delay} seconds"
    )

    %{media_item_id: media_item_id}
    |> PlexLookupWorker.new(schedule_in: delay)
    |> Oban.insert()
  end

  defp lookup_delay_seconds do
    Application.get_env(:pinchflat, :plex_lookup_delay_seconds, @default_lookup_delay_seconds)
  end

  defp plex_runner do
    Application.get_env(:pinchflat, :plex_runner, PlexApi)
  end
end
