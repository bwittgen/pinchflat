defmodule PinchflatWeb.Api.SourcesControllerTest do
  use PinchflatWeb.ConnCase

  import Pinchflat.MediaFixtures
  import Pinchflat.SourcesFixtures
  import Pinchflat.ProfilesFixtures

  alias Pinchflat.Settings
  alias Pinchflat.SlowIndexing.MediaCollectionIndexingWorker

  defp api_conn(conn) do
    route_token = Settings.get!(:route_token)

    conn
    |> put_req_header("authorization", "Bearer #{route_token}")
    |> put_req_header("accept", "application/json")
  end

  describe "GET /api/sources" do
    test "returns a list of sources", %{conn: conn} do
      source = source_fixture()

      conn =
        conn
        |> api_conn()
        |> get("/api/sources")

      assert %{"data" => data} = json_response(conn, 200)
      assert is_list(data)
      assert length(data) >= 1
      assert Enum.any?(data, fn s -> s["id"] == source.id end)
    end

    test "returns 401 without auth", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> get("/api/sources")

      assert conn.status == 401
    end

    test "returns 401 with invalid token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer invalid-token")
        |> put_req_header("accept", "application/json")
        |> get("/api/sources")

      assert conn.status == 401
    end
  end

  describe "GET /api/sources/:id" do
    test "returns a single source", %{conn: conn} do
      source = source_fixture()

      conn =
        conn
        |> api_conn()
        |> get("/api/sources/#{source.id}")

      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == source.id
      assert data["custom_name"] == source.custom_name
    end

    test "returns 404 JSON for non-existent source", %{conn: conn} do
      conn =
        conn
        |> api_conn()
        |> get("/api/sources/999999")

      assert %{"error" => "Not found"} = json_response(conn, 404)
    end

    test "returns 404 JSON for invalid source ID", %{conn: conn} do
      conn =
        conn
        |> api_conn()
        |> get("/api/sources/invalid")

      assert %{"error" => "Not found"} = json_response(conn, 404)
    end
  end

  describe "POST /api/sources" do
    setup do
      media_profile = media_profile_fixture()
      {:ok, %{media_profile: media_profile}}
    end

    test "returns 422 with invalid params", %{conn: conn} do
      conn =
        conn
        |> api_conn()
        |> post("/api/sources", %{"source" => %{"original_url" => nil}})

      assert %{"errors" => _errors} = json_response(conn, 422)
    end
  end

  describe "GET /api/sources/:source_id/media" do
    test "returns media items for a source", %{conn: conn} do
      source = source_fixture()
      media_item = media_item_fixture(%{source_id: source.id})

      conn =
        conn
        |> api_conn()
        |> get("/api/sources/#{source.id}/media")

      assert %{"data" => data} = json_response(conn, 200)
      assert is_list(data)
      assert Enum.any?(data, fn m -> m["id"] == media_item.id end)
    end

    test "returns empty list when source has no media", %{conn: conn} do
      source = source_fixture()

      conn =
        conn
        |> api_conn()
        |> get("/api/sources/#{source.id}/media")

      assert %{"data" => []} = json_response(conn, 200)
    end

    test "returns 404 JSON for non-existent source", %{conn: conn} do
      conn =
        conn
        |> api_conn()
        |> get("/api/sources/999999/media")

      assert %{"error" => "Not found"} = json_response(conn, 404)
    end

    test "returns 404 JSON for invalid source ID", %{conn: conn} do
      conn =
        conn
        |> api_conn()
        |> get("/api/sources/invalid/media")

      assert %{"error" => "Not found"} = json_response(conn, 404)
    end
  end

  describe "POST /api/sources/:source_id/force_index" do
    test "enqueues an indexing task", %{conn: conn} do
      source = source_fixture()

      conn =
        conn
        |> api_conn()
        |> post("/api/sources/#{source.id}/force_index")

      assert %{"data" => %{"message" => "Index enqueued."}} = json_response(conn, 200)
      assert_enqueued(worker: MediaCollectionIndexingWorker)
    end

    test "returns 404 JSON for non-existent source", %{conn: conn} do
      conn =
        conn
        |> api_conn()
        |> post("/api/sources/999999/force_index")

      assert %{"error" => "Not found"} = json_response(conn, 404)
    end

    test "returns 404 JSON for invalid source ID", %{conn: conn} do
      conn =
        conn
        |> api_conn()
        |> post("/api/sources/invalid/force_index")

      assert %{"error" => "Not found"} = json_response(conn, 404)
    end
  end

  describe "authentication" do
    test "allows access with basic auth when configured", %{conn: conn} do
      username = "testuser"
      password = "testpass"
      Application.put_env(:pinchflat, :basic_auth_username, username)
      Application.put_env(:pinchflat, :basic_auth_password, password)

      source_fixture()

      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> put_req_header(
          "authorization",
          "Basic " <> Base.encode64("#{username}:#{password}")
        )
        |> get("/api/sources")

      Application.put_env(:pinchflat, :basic_auth_username, "")
      Application.put_env(:pinchflat, :basic_auth_password, "")

      assert %{"data" => _data} = json_response(conn, 200)
    end
  end
end
