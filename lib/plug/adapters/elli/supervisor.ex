defmodule Plug.Adapters.Elli.Supervisor do

  @moduledoc false
  use Supervisor.Behaviour

  def start_link do
    :supervisor.start_link({ :local, __MODULE__ }, __MODULE__, [])
  end

  def init([]) do
    supervise([], strategy: :one_for_one)
  end

  def start_elli(ref, options) do
    case :supervisor.start_child(__MODULE__, worker(:elli, [options], [id: ref])) do
      { :ok, _ } ->
        { :ok, ref }
      { :error, { :already_started, _ } } ->
        { :error, { :already_started, ref } }
      other_error -> other_error
    end
  end

  def stop_elli(ref) do
    case :supervisor.terminate_child(__MODULE__, ref) do
      :ok -> :supervisor.delete_child(__MODULE__, ref)
      error -> error
    end
  end
end
