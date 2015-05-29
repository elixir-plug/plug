defmodule Plug.LoggerTest do
  use ExUnit.Case
  use Plug.Test

  import ExUnit.CaptureIO
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
    capture_log fn -> MyPlug.call(conn, []) end
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

  defp capture_log(fun) do
    data = capture_io(:user, fn ->
      Process.put(:capture_log, fun.())
      Logger.flush()
    end) |> String.split("\n", trim: true)
    {Process.get(:capture_log), data}
  end

  test "logs proper message to console" do
    {_conn, [first_message, second_message]} = conn(:get, "/") |> call
    assert Regex.match?(~r/\[info\]  GET \//u, first_message)
    assert Regex.match?(~r/Sent 200 in [0-9]+[µm]s/u, second_message)

    {_conn, [first_message, second_message]} = conn(:get, "/hello/world") |> call
    assert Regex.match?(~r/\[info\]  GET \/hello\/world/u, first_message)
    assert Regex.match?(~r/Sent 200 in [0-9]+[µm]s/u, second_message)
  end

  test "logs chunked if chunked reply" do
    {_, [_, second_message]} = capture_log(fn ->
       conn(:get, "/hello/world") |> MyChunkedPlug.call([])
    end)
    assert Regex.match?(~r/Chunked 200 in [0-9]+[µm]s/u, second_message)
  end

  test "logs halted connections if :log_on_halt is true" do
    {_conn, [output]} = capture_log fn ->
      conn(:get, "/foo") |> MyHaltingPlug.call([])
    end

    assert output =~ "Plug.LoggerTest.MyHaltingPlug halted in :halter/2"
  end
end
