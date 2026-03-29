defmodule Pinchflat.Plex.PlexScanWorker do
  @moduledoc """
  Oban worker that triggers Plex library scans and media matching
  after downloads complete.
  """

  use Oban.Worker,
    queue: :local_data,
    priority: 3,
    max_attempts: 3,
    tags: ["plex", "library_scan"]

  require Logger

  alias Pinchflat.Media
  alias Pinchflat.Plex.PlexApi

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
      media_item = Media.get_media_item!(media_item_id)

      Logger.info("Triggering Plex library scan for media item #{media_item_id}")

      with :ok <- plex_api.trigger_library_scan(),
           {:ok, plex_item} <- plex_api.find_media_item(media_item),
           {:ok, mismatches} <- plex_api.check_metadata(media_item, plex_item),
           {:ok, watch_status} <- plex_api.sync_watch_status(media_item, plex_item) do
        log_results(media_item_id, mismatches, watch_status)
        :ok
      else
        {:error, reason} ->
          Logger.warning("Plex sync incomplete for media item #{media_item_id}: #{inspect(reason)}")
          :ok
      end
    else
      Logger.debug("Plex integration not enabled, skipping scan for media item #{media_item_id}")
      :ok
    end
  rescue
    Ecto.NoResultsError ->
      Logger.info("#{__MODULE__} discarded: media item #{media_item_id} not found")
      :ok
  end

  defp log_results(media_item_id, mismatches, watch_status) do
    if Enum.any?(mismatches) do
      Logger.info(
        "Plex metadata mismatches for media item #{media_item_id}: #{inspect(mismatches)}"
      )
    end

    Logger.debug("Plex watch status for media item #{media_item_id}: #{inspect(watch_status)}")
  end

  defp plex_runner do
    Application.get_env(:pinchflat, :plex_runner, PlexApi)
  end
end
