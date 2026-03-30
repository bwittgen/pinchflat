defmodule PinchflatWeb.Api.SourcesController do
  use PinchflatWeb, :controller
  use Pinchflat.Media.MediaQuery

  alias Pinchflat.Repo
  alias Pinchflat.Sources
  alias Pinchflat.SlowIndexing.SlowIndexingHelpers

  action_fallback PinchflatWeb.Api.FallbackController

  def index(conn, _params) do
    sources =
      Sources.list_sources()
      |> Repo.preload(:media_profile)

    json(conn, %{data: sources})
  end

  def show(conn, %{"id" => id}) do
    source =
      Sources.get_source!(id)
      |> Repo.preload(:media_profile)

    json(conn, %{data: source})
  end

  def create(conn, %{"source" => source_params}) do
    with {:ok, source} <- Sources.create_source(source_params) do
      source = Repo.preload(source, :media_profile)

      conn
      |> put_status(:created)
      |> json(%{data: source})
    end
  end

  def media(conn, %{"source_id" => source_id}) do
    source = Sources.get_source!(source_id)

    media_items =
      MediaQuery.new()
      |> where(^MediaQuery.for_source(source))
      |> order_by(desc: :inserted_at)
      |> Repo.all()
      |> Repo.preload(:source)

    json(conn, %{data: media_items})
  end

  def force_index(conn, %{"source_id" => source_id}) do
    source = Sources.get_source!(source_id)
    SlowIndexingHelpers.kickoff_indexing_task(source, %{force: true})

    json(conn, %{data: %{message: "Index enqueued."}})
  end
end
