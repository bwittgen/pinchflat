defmodule Pinchflat.Plex.PlexScanWorkerTest do
  use Pinchflat.DataCase

  import Pinchflat.MediaFixtures

  alias Pinchflat.Plex.PlexScanWorker

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
      expect(PlexApiMock, :find_media_item, fn mi -> assert mi.id == media_item.id; {:ok, %{"ratingKey" => "1"}} end)
      expect(PlexApiMock, :check_metadata, fn _mi, _pi -> {:ok, []} end)
      expect(PlexApiMock, :sync_watch_status, fn _mi, _pi -> {:ok, %{watched: false}} end)

      assert :ok = perform_job(PlexScanWorker, %{media_item_id: media_item.id})
    end

    test "skips scan when plex is not enabled", %{media_item: media_item} do
      expect(PlexApiMock, :enabled?, fn -> false end)

      assert :ok = perform_job(PlexScanWorker, %{media_item_id: media_item.id})
    end

    test "does not blow up if the media item doesn't exist" do
      stub(PlexApiMock, :enabled?, fn -> true end)

      assert :ok = perform_job(PlexScanWorker, %{media_item_id: 0})
    end

    test "handles library scan failure gracefully", %{media_item: media_item} do
      expect(PlexApiMock, :enabled?, fn -> true end)
      expect(PlexApiMock, :trigger_library_scan, fn nil -> {:error, "connection refused"} end)

      assert :ok = perform_job(PlexScanWorker, %{media_item_id: media_item.id})
    end

    test "handles find_media_item failure gracefully", %{media_item: media_item} do
      expect(PlexApiMock, :enabled?, fn -> true end)
      expect(PlexApiMock, :trigger_library_scan, fn nil -> :ok end)
      expect(PlexApiMock, :find_media_item, fn _mi -> {:error, "not found"} end)

      assert :ok = perform_job(PlexScanWorker, %{media_item_id: media_item.id})
    end

    test "logs metadata mismatches", %{media_item: media_item} do
      mismatches = [%{field: "title", pinchflat_value: "A", plex_value: "B"}]

      expect(PlexApiMock, :enabled?, fn -> true end)
      expect(PlexApiMock, :trigger_library_scan, fn nil -> :ok end)
      expect(PlexApiMock, :find_media_item, fn _mi -> {:ok, %{"ratingKey" => "1"}} end)
      expect(PlexApiMock, :check_metadata, fn _mi, _pi -> {:ok, mismatches} end)
      expect(PlexApiMock, :sync_watch_status, fn _mi, _pi -> {:ok, %{watched: true}} end)

      assert :ok = perform_job(PlexScanWorker, %{media_item_id: media_item.id})
    end
  end
end
