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

  def media(conn, %{"source_id" => source_id} = params) do
    source = Sources.get_source!(source_id)

    page = max(parse_int(params["page"], 1), 1)
    page_size = params["page_size"] |> parse_int(50) |> max(1) |> min(100)

    base_query =
      MediaQuery.new()
      |> where(^MediaQuery.for_source(source))
      |> order_by(desc: :inserted_at)

    total_count = Repo.aggregate(base_query, :count)
    total_pages = max(ceil(total_count / page_size), 1)

    media_items =
      base_query
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))
      |> Repo.all()
      |> Repo.preload(:source)

    json(conn, %{
      data: media_items,
      page: page,
      page_size: page_size,
      total_count: total_count,
      total_pages: total_pages
    })
  end

  defp parse_int(nil, default), do: default
  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end
  defp parse_int(value, _default) when is_integer(value), do: value
  defp parse_int(_, default), do: default

  def force_index(conn, %{"source_id" => source_id}) do
    source = Sources.get_source!(source_id)
    SlowIndexingHelpers.kickoff_indexing_task(source, %{force: true})

    json(conn, %{data: %{message: "Index enqueued."}})
  end
end
