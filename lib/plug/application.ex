defmodule Plug.Application do
  @moduledoc false
  use Application

  def start(_, _) do
    # While Plug.Crypto provides its own cache, Plug ship its own too,
    # both to keep storages separate and for backwards compatibility.
    Plug.Keys = :ets.new(Plug.Keys, [:named_table, :public, read_concurrency: true])

    children = [
      Plug.Upload
    ]

    Supervisor.start_link(children, name: __MODULE__, strategy: :one_for_one)
  end
end
