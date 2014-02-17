defmodule Plug.CommonLoggerTest do
  use ExUnit.Case, async: true
  use Plug.Test

  import ExUnit.CaptureIO

  defmodule CustomLogger do
    def info(output) do
      IO.puts("> #{output}")
    end
  end

  test "log request with IO.puts by default" do
    output = capture_io(fn -> wrap(conn(:get, "/?foo=bar")) end)
    assert Regex.match?(~r/- - \[([^\]]+)\] "GET \/\?foo=bar HTTP\/1.1" 200 -/, output)
  end

  test "log request with a custom logger" do
    custom_logger = Plug.CommonLogger.init(fun: &CustomLogger.info/1)
    output = capture_io(fn -> wrap(conn(:get, "/?foo=bar"), custom_logger) end)
    assert Regex.match?(~r/> - - \[([^\]]+)\] "GET \/\?foo=bar HTTP\/1.1" 200 -/, output)
  end

  @common_logger Plug.CommonLogger.init([])

  defp wrap(conn, opts \\ @common_logger) do
    fun = fn conn -> Plug.Connection.send_resp(conn, 200, "Hello, world") end
    Plug.CommonLogger.wrap(conn, opts, fun)
  end
end
