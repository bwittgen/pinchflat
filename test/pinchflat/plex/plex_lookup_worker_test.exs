defmodule Pinchflat.Plex.PlexLookupWorkerTest do
  use Pinchflat.DataCase

  import Pinchflat.MediaFixtures

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

  describe "perform/1" do
    test "looks up media item in plex when enabled", %{media_item: media_item} do
      expect(PlexApiMock, :enabled?, fn -> true end)
      expect(PlexApiMock, :find_media_item, fn mi -> assert mi.id == media_item.id; {:ok, %{"ratingKey" => "1"}} end)
      expect(PlexApiMock, :check_metadata, fn _mi, _pi -> {:ok, []} end)
      expect(PlexApiMock, :sync_watch_status, fn _mi, _pi -> {:ok, %{watched: false}} end)

      assert :ok = perform_job(PlexLookupWorker, %{media_item_id: media_item.id})
    end

    test "skips lookup when plex is not enabled", %{media_item: media_item} do
      expect(PlexApiMock, :enabled?, fn -> false end)

      assert :ok = perform_job(PlexLookupWorker, %{media_item_id: media_item.id})
    end

    test "does not blow up if the media item doesn't exist" do
      stub(PlexApiMock, :enabled?, fn -> true end)

      assert :ok = perform_job(PlexLookupWorker, %{media_item_id: 0})
    end

    test "handles find_media_item failure gracefully", %{media_item: media_item} do
      expect(PlexApiMock, :enabled?, fn -> true end)
      expect(PlexApiMock, :find_media_item, fn _mi -> {:error, "not found"} end)

      assert :ok = perform_job(PlexLookupWorker, %{media_item_id: media_item.id})
    end

    test "logs metadata mismatches", %{media_item: media_item} do
      mismatches = [%{field: "title", pinchflat_value: "A", plex_value: "B"}]

      expect(PlexApiMock, :enabled?, fn -> true end)
      expect(PlexApiMock, :find_media_item, fn _mi -> {:ok, %{"ratingKey" => "1"}} end)
      expect(PlexApiMock, :check_metadata, fn _mi, _pi -> {:ok, mismatches} end)
      expect(PlexApiMock, :sync_watch_status, fn _mi, _pi -> {:ok, %{watched: true}} end)

      assert :ok = perform_job(PlexLookupWorker, %{media_item_id: media_item.id})
    end
  end
end
