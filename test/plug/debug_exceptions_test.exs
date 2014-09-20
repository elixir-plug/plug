defmodule Plug.DebugExceptionsTest do
  use ExUnit.Case, async: true
  use Plug.Test
  import ExUnit.CaptureIO

  defmodule Router do
    use Plug.Builder
    use Plug.DebugExceptions

    plug :boom

    def boom(conn, _opts) do
      assign(conn, :entered_stack, true)
      raise ArgumentError
    end
  end

  def capture_log(fun) do
    data = capture_io(:user, fn ->
      Process.put(:capture_log, fun.())
      Logger.flush()
    end) |> String.split("\n", trim: true)
    {Process.get(:capture_log), data}
  end

  test "call/2 is overridden and error is caught" do
    conn = conn(:get, "/")
           |> Router.call([])

    assert conn.state == :sent
    assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
  end

  test "verify logger" do
    {_conn, log} = capture_log fn ->
      conn(:get, "/") |> Router.call([])
    end
    assert String.contains?(List.first(log), "[error] ArgumentError: argument error")
  end
end
