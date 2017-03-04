defmodule Plug.Adapters.TranslatorTest do
  use ExUnit.Case

  import ExUnit.CaptureLog

  def init(opts) do
    opts
  end

  def call(%{path_info: ["warn"]}, _opts) do
    raise Plug.Parsers.UnsupportedMediaTypeError, media_type: "foo/bar"
  end

  def call(%{path_info: ["error"]}, _opts) do
    raise "oops"
  end

  test "ranch/cowboy 500 logs" do
    {:ok, _pid} = Plug.Adapters.Cowboy.http __MODULE__, [], port: 9001
    on_exit fn -> Plug.Adapters.Cowboy.shutdown(__MODULE__.HTTP) end

    output = capture_log fn ->
      :hackney.get("http://127.0.0.1:9001/error", [], "", [])
    end

    assert output =~ ~r"#PID<0\.\d+\.0> running Plug\.Adapters\.TranslatorTest terminated"
    assert output =~ "Server: 127.0.0.1:9001 (http)"
    assert output =~ "Request: GET /"
    assert output =~ "** (exit) an exception was raised:"
    assert output =~ "** (RuntimeError) oops"
  end

  test "ranch/cowboy non-500 skips" do
    {:ok, _pid} = Plug.Adapters.Cowboy.http __MODULE__, [], port: 9002
    on_exit fn -> Plug.Adapters.Cowboy.shutdown(__MODULE__.HTTP) end

    output = capture_log fn ->
      :hackney.get("http://127.0.0.1:9002/warn", [], "", [])
    end

    refute output =~ ~r"#PID<0\.\d+\.0> running Plug\.Adapters\.TranslatorTest terminated"
    refute output =~ "Server: 127.0.0.1:9002 (http)"
    refute output =~ "Request: GET /"
    refute output =~ "** (exit) an exception was raised:"
  end
end
