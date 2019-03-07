defmodule Plug.Telemetry do
  @moduledoc """
  A plug to instrument the pipeline with `:telemetry` events.
  """

  @behaviour Plug

  @impl true
  def init(opts) do
    event_prefix = ensure_event_prefix!(opts)
    ensure_valid_event_prefix!(event_prefix)
    start_event = event_prefix ++ [:call, :start]
    stop_event = event_prefix ++ [:call, :stop]
    {start_event, stop_event}
  end

  @impl true
  def call(conn, {start_event, stop_event}) do
    start_time = System.monotonic_time()
    :telemetry.execute(start_event, %{}, %{conn: conn})

    Plug.Conn.register_before_send(conn, fn conn ->
      duration = System.monotonic_time() - start_time

      :telemetry.execute(stop_event, %{duration: duration}, %{
        conn: conn
      })

      conn
    end)
  end

  defp ensure_event_prefix!(opts) do
    case Keyword.fetch(opts, :event_prefix) do
      {:ok, event_prefix} ->
        event_prefix

      _ ->
        raise ArgumentError, ":event_prefix is required"
    end
  end

  defp ensure_valid_event_prefix!(event_prefix) do
    if is_list(event_prefix) && Enum.all?(event_prefix, &is_atom/1) do
      :ok
    else
      raise ArgumentError,
            "expected :event_prefix to be a list of atoms, got: #{inspect(event_prefix)}"
    end
  end
end
