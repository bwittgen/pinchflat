defmodule Pinchflat.Metadata.NfoRebuildWorkerTest do
  use Pinchflat.DataCase

  import Pinchflat.MediaFixtures
  import Pinchflat.SourcesFixtures

  alias Pinchflat.Repo
  alias Pinchflat.Metadata.NfoRebuildWorker
  alias Pinchflat.Metadata.MetadataFileHelpers
  alias Pinchflat.Utils.FilesystemUtils

  setup do
    source = source_fixture()
    {:ok, %{source: source}}
  end

  describe "kickoff_with_task/2" do
    test "starts the worker", %{source: source} do
      assert [] = all_enqueued(worker: NfoRebuildWorker)
      assert {:ok, _} = NfoRebuildWorker.kickoff_with_task(source)
      assert [_] = all_enqueued(worker: NfoRebuildWorker)
    end
  end

  describe "perform/1" do
    test "rebuilds NFO for media items with metadata", %{source: source} do
      {media_item, nfo_filepath} = create_media_item_with_compressed_metadata(source)

      perform_job(NfoRebuildWorker, %{"id" => source.id})

      updated = Repo.reload!(media_item)
      assert updated.nfo_filepath == nfo_filepath
      assert File.exists?(nfo_filepath)

      nfo_content = File.read!(nfo_filepath)
      assert String.contains?(nfo_content, "<episodedetails>")
      assert String.contains?(nfo_content, "<title>Pinchflat Example Video</title>")
    end

    test "skips media items without media_filepath", %{source: source} do
      media_item = media_item_fixture(%{source_id: source.id, media_filepath: nil})

      perform_job(NfoRebuildWorker, %{"id" => source.id})

      updated = Repo.reload!(media_item)
      refute updated.nfo_filepath
    end

    test "skips media items without metadata", %{source: source} do
      media_item = media_item_fixture(%{source_id: source.id})

      perform_job(NfoRebuildWorker, %{"id" => source.id})

      updated = Repo.reload!(media_item)
      refute updated.nfo_filepath
    end

    test "rebuilds source-level tvshow.nfo when metadata available", %{source: source} do
      series_dir = Path.join(Application.get_env(:pinchflat, :media_directory), "#{:rand.uniform(1_000_000)}")
      File.mkdir_p!(series_dir)

      source_metadata_filepath = compress_and_store_source_metadata(source)

      {:ok, source} =
        Pinchflat.Sources.update_source(
          source,
          %{
            series_directory: series_dir,
            metadata: %{metadata_filepath: source_metadata_filepath}
          },
          run_post_commit_tasks: false
        )

      perform_job(NfoRebuildWorker, %{"id" => source.id})

      updated_source = Repo.reload!(source)
      expected_nfo = Path.join(series_dir, "tvshow.nfo")
      assert updated_source.nfo_filepath == expected_nfo
      assert File.exists?(expected_nfo)

      nfo_content = File.read!(expected_nfo)
      assert String.contains?(nfo_content, "<tvshow>")
    end

    test "skips source NFO when series_directory is nil", %{source: source} do
      perform_job(NfoRebuildWorker, %{"id" => source.id})

      updated_source = Repo.reload!(source)
      refute updated_source.nfo_filepath
    end

    test "returns :ok even when source not found" do
      assert :ok = perform_job(NfoRebuildWorker, %{"id" => -1})
    end
  end

  defp create_media_item_with_compressed_metadata(source) do
    base_dir = Path.join(Application.get_env(:pinchflat, :media_directory), "#{:rand.uniform(1_000_000)}")
    media_filepath = Path.join([base_dir, "Season 01", "video - s01e01.mkv"])
    nfo_filepath = Path.rootname(media_filepath) <> ".nfo"

    FilesystemUtils.cp_p!(media_filepath_fixture(), media_filepath)

    media_item = media_item_fixture(%{source_id: source.id, media_filepath: media_filepath})

    metadata = read_test_metadata()
    compressed_path = MetadataFileHelpers.compress_and_store_metadata_for(media_item, metadata)

    {:ok, media_item} =
      Pinchflat.Media.update_media_item(media_item, %{
        metadata: %{
          metadata_filepath: compressed_path,
          thumbnail_filepath: thumbnail_filepath_fixture()
        }
      })

    {media_item, nfo_filepath}
  end

  defp compress_and_store_source_metadata(source) do
    metadata = read_test_metadata()
    MetadataFileHelpers.compress_and_store_metadata_for(source, metadata)
  end

  defp read_test_metadata do
    "media_metadata"
    |> render_metadata()
    |> Phoenix.json_library().decode!()
  end
end
