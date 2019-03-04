defmodule Plug.Telemetry do
  @moduledoc """
  A plug to instrument the pipeline with `:telemetry` events.
  """

  @behaviour Plug

  @impl true
  def init(_), do: []

  @impl true
  def call(conn, _opts) do
    time = System.monotonic_time()
    :telemetry.execute([:plug, :call, :start], %{}, %{conn: conn})

    conn
    |> Plug.Conn.put_private(:plug_telemetry_start_time, time)
    |> Plug.Conn.register_before_send(&emit_stop_event/1)
  end

  defp emit_stop_event(conn) do
    time = System.monotonic_time() - conn.private[:plug_telemetry_start_time]
    :telemetry.execute([:plug, :call, :stop], %{time: time}, %{conn: conn, status: conn.status})
    conn
  end
end
