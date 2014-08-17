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

  defp capture_log(fun) do
    data = capture_io(:user, fn ->
      Process.put(:capture_log, fun.())
      Logger.flush()
    end) |> String.split("\n", trim: true)
    {Process.get(:capture_log), data}
  end

  test "logs proper message to console" do
    {_conn, [first_message, second_message]} = conn(:get, "/hello/world") |> call
    assert Regex.match?(~r/request_id=[^-A-Za-z0-9+\/=]|=[^=]|={3,} [info]  GET hello\/world/u, first_message)
    assert Regex.match?(~r/Sent 200 in [0-9]+[µm]s/u, second_message)
  end

  test "adds request id to headers" do
    {conn, _} = conn(:get, "/hello/work") |> call
    refute Plug.Conn.get_resp_header(conn, "x-request-id") == nil
  end

  test "returns request id from request headers" do
    request_id = "01234567890123456789"
    {conn, _}  = conn(:get, "/hello/work")
                 |> put_req_header("x-request-id", request_id)
                 |> call

    assert Plug.Conn.get_resp_header(conn, "x-request-id") == [request_id]
  end

  test "generates new request id for invalid request_id" do
    request_id = "01234567890"
    {conn, _}  = conn(:get, "/hello/work")
                 |> put_req_header("x-request-id", request_id)
                 |> call

    refute Plug.Conn.get_resp_header(conn, "x-request-id") == [request_id]
  end

  test "logs chunked if chunked reply" do
    {_, [_, second_message]} = capture_log(fn ->
       conn(:get, "/hello/world") |> MyChunkedPlug.call([])
    end)
    assert Regex.match?(~r/Chunked 200 in [0-9]+[µm]s/u, second_message)
  end
end
