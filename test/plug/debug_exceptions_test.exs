defmodule Plug.DebugExceptionsTest do
  use ExUnit.Case
  use Plug.Test
  import ExUnit.CaptureIO

  defmodule Router do
    use Plug.Builder
    use Plug.DebugExceptions

    plug :boom

    def boom(_conn, _opts) do
      raise ArgumentError
    end
  end

  defmodule Overridable do
    use Plug.Builder
    use Plug.DebugExceptions
    require Logger

    plug :boom

    def boom(_conn, _opts) do
      raise ArgumentError
    end

    defp debug_template(_err) do
      "<h1>Foo</h1>"
    end

    defp log_error(_err) do
      Logger.error fn ->
        "Overridden!"
      end
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
    {conn, _log} = capture_log fn ->
      conn(:get, "/") |> Router.call([])
    end

    assert conn.state == :sent
    assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
    assert String.contains?(conn.resp_body, "<h2>(ArgumentError) argument error</h2>")
  end

  test "verify logger" do
    {_conn, log} = capture_log fn ->
      conn(:get, "/") |> Router.call([])
    end

    assert String.contains?(List.first(log), "[error] ** (ArgumentError) argument error")
    trace = "    test/plug/debug_exceptions_test.exs:13: Plug.DebugExceptionsTest.Router.boom/2"
    assert Enum.member?(log, trace)
  end

  test "debug template is overridable" do
    {conn, _log} = capture_log fn ->
      conn(:get, "/") |> Overridable.call([])
    end

    assert conn.resp_body == "<h1>Foo</h1>"
  end

  test "error logging is overridable" do
    {_conn, log} = capture_log fn ->
      conn(:get, "/") |> Overridable.call([])
    end

    assert String.contains?(List.first(log), "Overridden!")
  end
end
