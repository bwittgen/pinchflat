defmodule PinchflatWeb.Api.SourcesController do
  use PinchflatWeb, :controller
  use Pinchflat.Media.MediaQuery

  import PinchflatWeb.Api.ErrorHelpers

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
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
    Ecto.Query.CastError -> {:error, :not_found}
  end

  def create(conn, %{"source" => source_params}) do
    case Sources.create_source(source_params) do
      {:ok, source} ->
        source = Repo.preload(source, :media_profile)

        conn
        |> put_status(:created)
        |> json(%{data: source})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_changeset_errors(changeset)})
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
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
    Ecto.Query.CastError -> {:error, :not_found}
  end

  def force_index(conn, %{"source_id" => source_id}) do
    source = Sources.get_source!(source_id)
    SlowIndexingHelpers.kickoff_indexing_task(source, %{force: true})

    json(conn, %{data: %{message: "Index enqueued."}})
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
    Ecto.Query.CastError -> {:error, :not_found}
  end
end
