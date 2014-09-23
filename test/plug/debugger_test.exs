defmodule Plug.DebuggerTest do
  use ExUnit.Case
  use Plug.Test
  import ExUnit.CaptureIO

  defmodule Router do
    use Plug.Builder
    use Plug.Debugger, [root: Path.expand("plug"), sources: ["plug/**/*"]]

    plug :boom

    def boom(_conn, _opts) do
      raise ArgumentError
    end

    # Overrride log_error/1 to silence default logs
    def log_error(_err) do
    end
  end

  defmodule Logs do
    use Plug.Builder
    use Plug.Debugger, [root: Path.expand("plug"), sources: ["plug/**/*"]]

    plug :boom

    def boom(_conn, _opts) do
      raise ArgumentError
    end
  end

  defmodule Exit do
    use Plug.Builder
    use Plug.Debugger, [root: Path.expand("plug"), sources: ["plug/**/*"]]

    plug :boom

    def boom(_conn, _opts) do
      exit(:normal)
    end
  end

  defmodule Overridable do
    use Plug.Builder
    use Plug.Debugger, [root: Path.expand("plug"), sources: ["plug/**/*"]]
    require Logger

    plug :boom

    def boom(_conn, _opts) do
      raise ArgumentError
    end

    defp debug_template(_assigns) do
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
    conn = conn(:get, "/") |> Router.call([])

    assert conn.state == :sent
    assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
  end

  test "verify logger on error" do
    {_conn, log} = capture_log fn ->
      conn(:get, "/") |> Logs.call([])
    end
    trace = "    test/plug/debugger_test.exs:28: Plug.DebuggerTest.Logs.boom/2"

    assert String.contains?(List.first(log), "[error] ** (ArgumentError) argument error")
    assert Enum.member?(log, trace)
  end

  test "verify logger on exit" do
    {_conn, log} = capture_log fn ->
      conn(:get, "/") |> Exit.call([])
    end

    assert String.contains?(List.first(log), "[error] ** (exit) normal")
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

  ## Default Template

  test "prints exception name and title" do
    conn =  conn(:get, "/") |> Router.call([])

    assert conn.status == 500
    assert conn.resp_body =~ ~r"ArgumentError"
    assert conn.resp_body =~ ~r"argument error"
    assert conn.resp_body =~ ~r"ArgumentError at GET /"
  end

  test "shows shortcut file path, module and function" do
    conn = conn(:get, "/") |> Router.call([])

    assert conn.resp_body =~ ~r"\bplug/debugger_test.exs\b"
    assert conn.resp_body =~ ~r"\bPlug.DebuggerTest\b"
    assert conn.resp_body =~ ~r"\bboom/2\b"
  end

  test "shows snippets if they are part of the source_paths" do
    conn = conn(:get, "/") |> Router.call([])
    assert conn.resp_body =~ ~r"<h2 class=\"name\">Plug.DebuggerTest.Router</h2>"
  end

  test "does not show snippets if they are not part of the source_paths" do
    conn = conn(:get, "/") |> Router.call([])
    assert conn.resp_body =~ ~r"No code snippets for code outside the Dynamo"
  end
end
