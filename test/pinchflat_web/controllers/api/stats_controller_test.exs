defmodule PinchflatWeb.Api.StatsControllerTest do
  use PinchflatWeb.ConnCase

  alias Pinchflat.Settings

  defp api_conn(conn) do
    route_token = Settings.get!(:route_token)

    conn
    |> put_req_header("authorization", "Bearer #{route_token}")
    |> put_req_header("accept", "application/json")
  end

  describe "GET /api/stats" do
    test "returns queue and system stats", %{conn: conn} do
      conn =
        conn
        |> api_conn()
        |> get("/api/stats")

      assert %{"data" => data} = json_response(conn, 200)
      assert %{"queues" => queues, "system" => system} = data

      assert is_list(queues)
      assert is_map(system)
      assert Map.has_key?(system, "total_sources")
      assert Map.has_key?(system, "total_downloaded")
      assert Map.has_key?(system, "total_pending_downloads")
      assert Map.has_key?(system, "database_size")
    end

    test "returns 401 without auth", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> get("/api/stats")

      assert conn.status == 401
    end
  end
end
