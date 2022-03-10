defmodule Plug.LoggerTest do
  use ExUnit.Case
  use Plug.Test

  import ExUnit.CaptureLog

  require Logger

  defmodule MyPlug do
    use Plug.Builder

    plug Plug.Logger
    plug :passthrough

    defp passthrough(conn, _) do
      Plug.Conn.send_resp(conn, 200, "Passthrough")
    end
  end

  defp call(conn) do
    MyPlug.call(conn, [])
  end

  defmodule MyChunkedPlug do
    use Plug.Builder

    plug Plug.Logger
    plug :passthrough

    defp passthrough(conn, _) do
      Plug.Conn.send_chunked(conn, 200)
    end
  end

  defmodule MyHaltingPlug do
    use Plug.Builder, log_on_halt: :debug

    plug :halter
    defp halter(conn, _), do: halt(conn)
  end

  defmodule MyDebugLevelPlug do
    use Plug.Builder

    plug Plug.Logger, log: :debug
    plug :passthrough

    defp passthrough(conn, _) do
      Plug.Conn.send_resp(conn, 200, "Passthrough")
    end
  end

  test "logs proper message to console" do
    [first_message, second_message] =
      capture_log_lines(fn ->
        call(conn(:get, "/"))
      end)

    assert first_message =~ ~r"\[info\] GET /"u
    assert second_message =~ ~r"Sent 200 in [0-9]+[µm]s"u

    [first_message, second_message] =
      capture_log_lines(fn ->
        call(conn(:get, "/hello/world"))
      end)

    assert first_message =~ ~r"\[info\] GET /hello/world"u
    assert second_message =~ ~r"Sent 200 in [0-9]+[µm]s"u
  end

  test "logs paths with double slashes and trailing slash" do
    [first_message, _] =
      capture_log_lines(fn ->
        call(conn(:get, "/hello//world/"))
      end)

    assert first_message =~ ~r"/hello//world/"u
  end

  test "logs chunked if chunked reply" do
    [_, second_message] =
      capture_log_lines(fn ->
        MyChunkedPlug.call(conn(:get, "/hello/world"), [])
      end)

    assert second_message =~ ~r"Chunked 200 in [0-9]+[µm]s"u
  end

  test "logs halted connections if :log_on_halt is true" do
    [output] =
      capture_log_lines(fn ->
        MyHaltingPlug.call(conn(:get, "/foo"), [])
      end)

    assert output =~ "Plug.LoggerTest.MyHaltingPlug halted in :halter/2"
  end

  test "logs proper log level to console" do
    [first_message, second_message] =
      capture_log_lines(fn ->
        MyDebugLevelPlug.call(conn(:get, "/"), [])
      end)

    assert first_message =~ ~r"\[debug\] GET /"u
    assert second_message =~ ~r"Sent 200 in [0-9]+[µm]s"u
  end

  defp capture_log_lines(fun) do
    fun
    |> capture_log()
    |> String.split("\n", trim: true)
  end
end
