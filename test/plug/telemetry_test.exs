defmodule Plug.TelemetryTest do
  use ExUnit.Case, async: true
  use Plug.Test

  defmodule MyPlug do
    use Plug.Builder

    plug Plug.Telemetry

    plug :send_resp, 200

    def send_resp(conn, status) do
      Plug.Conn.send_resp(conn, status, "Response")
    end
  end

  defmodule MyNoSendPlug do
    use Plug.Builder

    plug Plug.Telemetry
  end

  setup do
    :telemetry.attach(
      :start,
      [:plug, :call, :start],
      fn _, measurements, metadata, _ ->
        send(self(), {:event, :start, measurements, metadata})
      end,
      nil
    )

    :telemetry.attach(
      :stop,
      [:plug, :call, :stop],
      fn _, measurements, metadata, _ ->
        send(self(), {:event, :stop, measurements, metadata})
      end,
      nil
    )

    on_exit(fn ->
      :telemetry.detach(:start)
      :telemetry.detach(:stop)
    end)
  end

  test "emits an event before the pipeline and before sending the response" do
    MyPlug.call(conn(:get, "/"), [])

    assert_received {:event, :start, measurements, metadata}
    assert %{} == measurements
    assert %{conn: conn} = metadata

    assert_received {:event, :stop, measurements, metadata}
    assert %{time: time} = measurements
    assert is_integer(time)
    assert %{conn: conn, status: 200} = metadata
    assert conn.state == :set
  end

  test "doesn't emit an event if the response is not sent" do
    MyNoSendPlug.call(conn(:get, "/"), [])

    assert_received {:event, :start, measurements, metadata}
    assert %{} == measurements
    assert %{conn: conn} = metadata

    refute_received {:event, :stop, _, _}
  end
end
