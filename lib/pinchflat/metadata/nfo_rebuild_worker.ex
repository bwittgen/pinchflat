defmodule Pinchflat.Metadata.NfoRebuildWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :local_data,
    tags: ["sources", "local_data"]

  require Logger

  alias __MODULE__
  alias Pinchflat.Repo
  alias Pinchflat.Media
  alias Pinchflat.Tasks
  alias Pinchflat.Sources
  alias Pinchflat.Metadata.NfoBuilder
  alias Pinchflat.Metadata.MetadataFileHelpers

  @doc """
  Starts the NFO rebuild worker for a source.

  Returns {:ok, %Task{}} | {:error, %Ecto.Changeset{}}
  """
  def kickoff_with_task(source, opts \\ []) do
    %{id: source.id}
    |> NfoRebuildWorker.new(opts)
    |> Tasks.create_job_with_task(source)
  end

  @doc """
  Rebuilds NFO files for all downloaded media items in a source
  using their stored metadata. Also rebuilds the source-level
  tvshow.nfo if metadata is available.

  Returns :ok
  """
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"id" => source_id}}) do
    source = Repo.preload(Sources.get_source!(source_id), [:metadata, media_items: :metadata])

    rebuild_media_item_nfos(source.media_items)
    rebuild_source_nfo(source)

    :ok
  rescue
    Ecto.NoResultsError -> Logger.info("#{__MODULE__} discarded: source #{source_id} not found")
    Ecto.StaleEntryError -> Logger.info("#{__MODULE__} discarded: source #{source_id} stale")
  end

  defp rebuild_media_item_nfos(media_items) do
    Enum.each(media_items, fn media_item ->
      with filepath when is_binary(filepath) <- media_item.media_filepath,
           %{metadata_filepath: meta_path} when is_binary(meta_path) <- media_item.metadata,
           {:ok, metadata} <- MetadataFileHelpers.read_compressed_metadata(meta_path) do
        nfo_filepath = Path.rootname(filepath) <> ".nfo"
        NfoBuilder.build_and_store_for_media_item(nfo_filepath, metadata)
        Media.update_media_item(media_item, %{nfo_filepath: nfo_filepath})
      else
        _ ->
          Logger.info("#{__MODULE__}: skipping media item #{media_item.id} - missing media file or metadata")
      end
    end)
  end

  defp rebuild_source_nfo(source) do
    with series_directory when is_binary(series_directory) <- source.series_directory,
         %{metadata_filepath: meta_path} when is_binary(meta_path) <- source.metadata,
         {:ok, metadata} <- MetadataFileHelpers.read_compressed_metadata(meta_path) do
      nfo_filepath = Path.join(series_directory, "tvshow.nfo")
      NfoBuilder.build_and_store_for_source(nfo_filepath, metadata)
      Sources.update_source(source, %{nfo_filepath: nfo_filepath}, run_post_commit_tasks: false)
    else
      _ ->
        Logger.info("#{__MODULE__}: skipping source #{source.id} NFO - missing series directory or metadata")
    end
  end
end
