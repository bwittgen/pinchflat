defmodule PinchflatWeb.Api.StatsController do
  use PinchflatWeb, :controller

  alias Pinchflat.Diagnostics.QueueDiagnostics

  def index(conn, _params) do
    queue_stats = QueueDiagnostics.get_all_queue_stats()
    system_stats = QueueDiagnostics.get_system_stats()

    json(conn, %{
      data: %{
        queues: queue_stats,
        system: system_stats
      }
    })
  end
end
