defmodule Pinchflat.Plex.PlexLookupWorker do
  @moduledoc """
  Oban worker that looks up media items in Plex and syncs metadata.

  Scheduled with a delay after PlexScanWorker triggers a library scan,
  giving Plex time to index newly downloaded files.
  """

  use Oban.Worker,
    queue: :local_data,
    priority: 3,
    max_attempts: 3,
    tags: ["plex", "media_lookup"]

  require Logger

  alias Pinchflat.Media
  alias Pinchflat.Plex.PlexApi

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"media_item_id" => media_item_id}}) do
    plex_api = plex_runner()

    if plex_api.enabled?() do
      media_item = Media.get_media_item!(media_item_id)

      Logger.info("Looking up Plex media for media item #{media_item_id}")

      with {:ok, plex_item} <- plex_api.find_media_item(media_item),
           {:ok, mismatches} <- plex_api.check_metadata(media_item, plex_item),
           {:ok, watch_status} <- plex_api.sync_watch_status(media_item, plex_item) do
        log_results(media_item_id, mismatches, watch_status)
        :ok
      else
        {:error, reason} ->
          Logger.warning("Plex lookup incomplete for media item #{media_item_id}: #{inspect(reason)}")
          :ok
      end
    else
      Logger.debug("Plex integration not enabled, skipping lookup for media item #{media_item_id}")
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
