defmodule Pinchflat.Plex.PlexScanWorkerTest do
  use Pinchflat.DataCase

  import Pinchflat.MediaFixtures

  alias Pinchflat.Plex.PlexScanWorker
  alias Pinchflat.Plex.PlexLookupWorker

  setup do
    stub(PlexApiMock, :enabled?, fn -> true end)
    stub(PlexApiMock, :trigger_library_scan, fn _section_id -> :ok end)
    stub(PlexApiMock, :find_media_item, fn _mi -> {:ok, %{"ratingKey" => "123", "title" => "Test"}} end)
    stub(PlexApiMock, :check_metadata, fn _mi, _pi -> {:ok, []} end)
    stub(PlexApiMock, :sync_watch_status, fn _mi, _pi -> {:ok, %{watched: false, view_count: 0}} end)

    stub(UserScriptRunnerMock, :run, fn _event_type, _data -> {:ok, "", 0} end)
    stub(HTTPClientMock, :get, fn _url, _headers, _opts -> {:ok, ""} end)

    media_item = media_item_fixture()
    {:ok, %{media_item: media_item}}
  end

  describe "enqueue_for_media_item/1" do
    test "enqueues a job for the media item", %{media_item: media_item} do
      assert [] = all_enqueued(worker: PlexScanWorker)
      assert {:ok, _} = PlexScanWorker.enqueue_for_media_item(media_item)
      assert [_] = all_enqueued(worker: PlexScanWorker)
    end
  end

  describe "perform/1" do
    test "triggers a library scan when plex is enabled", %{media_item: media_item} do
      expect(PlexApiMock, :enabled?, fn -> true end)
      expect(PlexApiMock, :trigger_library_scan, fn nil -> :ok end)

      assert :ok = perform_job(PlexScanWorker, %{media_item_id: media_item.id})
    end

    test "enqueues a lookup job after successful scan", %{media_item: media_item} do
      expect(PlexApiMock, :enabled?, fn -> true end)
      expect(PlexApiMock, :trigger_library_scan, fn nil -> :ok end)

      assert [] = all_enqueued(worker: PlexLookupWorker)
      assert :ok = perform_job(PlexScanWorker, %{media_item_id: media_item.id})
      assert [job] = all_enqueued(worker: PlexLookupWorker)
      assert job.args == %{"media_item_id" => media_item.id}
    end

    test "schedules lookup job with a delay", %{media_item: media_item} do
      expect(PlexApiMock, :enabled?, fn -> true end)
      expect(PlexApiMock, :trigger_library_scan, fn nil -> :ok end)

      assert :ok = perform_job(PlexScanWorker, %{media_item_id: media_item.id})
      assert [job] = all_enqueued(worker: PlexLookupWorker)
      assert job.scheduled_at > DateTime.utc_now()
    end

    test "skips scan when plex is not enabled", %{media_item: media_item} do
      expect(PlexApiMock, :enabled?, fn -> false end)

      assert :ok = perform_job(PlexScanWorker, %{media_item_id: media_item.id})
      assert [] = all_enqueued(worker: PlexLookupWorker)
    end

    test "does not enqueue lookup when scan fails", %{media_item: media_item} do
      expect(PlexApiMock, :enabled?, fn -> true end)
      expect(PlexApiMock, :trigger_library_scan, fn nil -> {:error, "connection refused"} end)

      assert :ok = perform_job(PlexScanWorker, %{media_item_id: media_item.id})
      assert [] = all_enqueued(worker: PlexLookupWorker)
    end

    test "handles library scan failure gracefully", %{media_item: media_item} do
      expect(PlexApiMock, :enabled?, fn -> true end)
      expect(PlexApiMock, :trigger_library_scan, fn nil -> {:error, "connection refused"} end)

      assert :ok = perform_job(PlexScanWorker, %{media_item_id: media_item.id})
    end
  end
end
