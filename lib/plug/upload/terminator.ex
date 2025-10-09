defmodule Plug.Upload.Terminator do
  @moduledoc false
  use GenServer

  @path_table Plug.Upload.Path

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok)
  end

  @impl true
  def init(:ok) do
    Process.flag(:trap_exit, true)
    {:ok, %{}}
  end

  @impl true
  def terminate(_reason, _state) do
    folder = fn entry, :ok -> delete_path(entry) end
    :ets.foldl(folder, :ok, @path_table)
  end

  defp delete_path({_pid, path}) do
    :file.delete(path, [:raw])
    :ok
  end
end
