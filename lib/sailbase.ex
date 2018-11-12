defmodule Sailbase do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec

    children = [
      worker(Sailbase.Worker, [])
    ]

    opts = [strategy: :one_for_one, name: Sailbase.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
