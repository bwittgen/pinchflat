defmodule Pinchflat.Plex.PlexApiTest do
  use Pinchflat.DataCase

  import Pinchflat.MediaFixtures

  alias Pinchflat.Settings
  alias Pinchflat.Plex.PlexApi

  setup do
    Settings.set(plex_server_url: "http://localhost:32400")
    Settings.set(plex_token: "test-token")

    :ok
  end

  describe "enabled?/0" do
    test "returns true when server URL and token are set" do
      assert PlexApi.enabled?()
    end

    test "returns false when server URL is nil" do
      Settings.set(plex_server_url: nil)
      refute PlexApi.enabled?()
    end

    test "returns false when token is nil" do
      Settings.set(plex_token: nil)
      refute PlexApi.enabled?()
    end

    test "returns false when server URL is empty" do
      Settings.set(plex_server_url: "")
      refute PlexApi.enabled?()
    end

    test "returns false when token is empty" do
      Settings.set(plex_token: "")
      refute PlexApi.enabled?()
    end
  end

  describe "trigger_library_scan/1" do
    test "scans a specific section when section_id is provided" do
      expect(HTTPClientMock, :get, fn url, headers ->
        assert url == "http://localhost:32400/library/sections/1/refresh"
        assert {"X-Plex-Token", "test-token"} in headers

        {:ok, ""}
      end)

      assert :ok = PlexApi.trigger_library_scan("1")
    end

    test "scans all sections when no section_id is provided" do
      sections_response =
        Phoenix.json_library().encode!(%{
          "MediaContainer" => %{
            "Directory" => [
              %{"key" => "1", "title" => "Movies"},
              %{"key" => "2", "title" => "TV Shows"}
            ]
          }
        })

      expect(HTTPClientMock, :get, fn url, _headers ->
        assert url =~ "/library/sections"
        refute url =~ "/refresh"
        {:ok, sections_response}
      end)

      expect(HTTPClientMock, :get, fn url, _headers ->
        assert url =~ "/library/sections/1/refresh"
        {:ok, ""}
      end)

      expect(HTTPClientMock, :get, fn url, _headers ->
        assert url =~ "/library/sections/2/refresh"
        {:ok, ""}
      end)

      assert :ok = PlexApi.trigger_library_scan()
    end

    test "returns error when HTTP request fails" do
      expect(HTTPClientMock, :get, fn _url, _headers ->
        {:error, "connection refused"}
      end)

      assert {:error, _} = PlexApi.trigger_library_scan("1")
    end
  end

  describe "find_media_item/1" do
    test "returns error when media item has no filepath" do
      media_item = media_item_fixture(%{media_filepath: nil})

      assert {:error, "Media item has no file path"} = PlexApi.find_media_item(media_item)
    end

    test "searches sections and returns a matching item" do
      media_item = media_item_fixture(%{title: "Test Video"})

      sections_response =
        Phoenix.json_library().encode!(%{
          "MediaContainer" => %{
            "Directory" => [%{"key" => "1", "title" => "Videos"}]
          }
        })

      search_response =
        Phoenix.json_library().encode!(%{
          "MediaContainer" => %{
            "Metadata" => [
              %{"title" => "Test Video", "ratingKey" => "123"}
            ]
          }
        })

      expect(HTTPClientMock, :get, fn url, _headers ->
        assert url =~ "/library/sections"
        refute url =~ "/search"
        {:ok, sections_response}
      end)

      expect(HTTPClientMock, :get, fn url, _headers ->
        assert url =~ "/search"
        {:ok, search_response}
      end)

      assert {:ok, %{"title" => "Test Video"}} = PlexApi.find_media_item(media_item)
    end

    test "returns error when no matching item found" do
      media_item = media_item_fixture(%{title: "Not Found Video"})

      sections_response =
        Phoenix.json_library().encode!(%{
          "MediaContainer" => %{
            "Directory" => [%{"key" => "1", "title" => "Videos"}]
          }
        })

      search_response =
        Phoenix.json_library().encode!(%{
          "MediaContainer" => %{
            "Metadata" => [
              %{"title" => "Different Video", "ratingKey" => "456"}
            ]
          }
        })

      expect(HTTPClientMock, :get, fn _url, _headers -> {:ok, sections_response} end)
      expect(HTTPClientMock, :get, fn _url, _headers -> {:ok, search_response} end)

      assert {:error, "Media not found in Plex"} = PlexApi.find_media_item(media_item)
    end
  end

  describe "check_metadata/2" do
    test "returns empty list when metadata matches" do
      media_item = media_item_fixture(%{title: "Test Video", duration_seconds: 300})

      plex_item = %{
        "title" => "Test Video",
        "duration" => 300_000
      }

      assert {:ok, []} = PlexApi.check_metadata(media_item, plex_item)
    end

    test "detects title mismatch" do
      media_item = media_item_fixture(%{title: "Original Title"})
      plex_item = %{"title" => "Different Title"}

      assert {:ok, mismatches} = PlexApi.check_metadata(media_item, plex_item)
      assert Enum.any?(mismatches, &(&1.field == "title"))
    end

    test "detects duration mismatch beyond tolerance" do
      media_item = media_item_fixture(%{title: "Test", duration_seconds: 300})
      plex_item = %{"title" => "Test", "duration" => 320_000}

      assert {:ok, mismatches} = PlexApi.check_metadata(media_item, plex_item)
      assert Enum.any?(mismatches, &(&1.field == "duration"))
    end

    test "allows duration within 5-second tolerance" do
      media_item = media_item_fixture(%{title: "Test", duration_seconds: 300})
      plex_item = %{"title" => "Test", "duration" => 303_000}

      assert {:ok, mismatches} = PlexApi.check_metadata(media_item, plex_item)
      refute Enum.any?(mismatches, &(&1.field == "duration"))
    end

    test "ignores nil values" do
      media_item = media_item_fixture(%{title: "Test", duration_seconds: nil})
      plex_item = %{"title" => "Test", "duration" => 300_000}

      assert {:ok, []} = PlexApi.check_metadata(media_item, plex_item)
    end
  end

  describe "sync_watch_status/2" do
    test "returns watch status for a plex item" do
      media_item = media_item_fixture()

      watch_response =
        Phoenix.json_library().encode!(%{
          "MediaContainer" => %{
            "Metadata" => [
              %{"viewCount" => 2, "lastViewedAt" => 1_609_459_200}
            ]
          }
        })

      expect(HTTPClientMock, :get, fn url, _headers ->
        assert url =~ "/library/metadata/123"
        {:ok, watch_response}
      end)

      assert {:ok, status} = PlexApi.sync_watch_status(media_item, %{"ratingKey" => "123"})
      assert status.watched == true
      assert status.view_count == 2
    end

    test "returns error when plex item has no rating key" do
      media_item = media_item_fixture()

      assert {:error, "Plex item has no rating key"} =
               PlexApi.sync_watch_status(media_item, %{})
    end
  end

  describe "test_connection/0" do
    test "returns ok when connection succeeds" do
      expect(HTTPClientMock, :get, fn url, headers ->
        assert url == "http://localhost:32400/"
        assert {"X-Plex-Token", "test-token"} in headers

        {:ok, Phoenix.json_library().encode!(%{"MediaContainer" => %{}})}
      end)

      assert :ok = PlexApi.test_connection()
    end

    test "returns error when connection fails" do
      expect(HTTPClientMock, :get, fn _url, _headers ->
        {:error, "connection refused"}
      end)

      assert {:error, _} = PlexApi.test_connection()
    end
  end
end
