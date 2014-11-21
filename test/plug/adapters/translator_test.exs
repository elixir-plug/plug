defmodule Plug.Adapters.TranslatorTest do
  use ExUnit.Case

  def init(opts) do
    opts
  end

  def call(_conn, _opts) do
    raise "oops"
  end

  import ExUnit.CaptureIO

  test "ranch/cowboy errors" do
    {:ok, _pid} = Plug.Adapters.Cowboy.http __MODULE__, [], port: 9001
    on_exit fn -> Plug.Adapters.Cowboy.shutdown(__MODULE__.HTTP) end

    output = capture_log fn ->
      :hackney.get("http://127.0.0.1:9001/", [], "", [])
    end

    assert output =~ ~r"#PID<0\.\d+\.0> running Plug\.Adapters\.TranslatorTest terminated"
    assert output =~ "Server: 127.0.0.1:9001 (http)"
    assert output =~ "Request: GET /"
    assert output =~ "** (exit) an exception was raised:"
    assert output =~ "** (RuntimeError) oops"
  end

  defp capture_log(fun) do
    capture_io(:user, fn ->
      fun.()
      Logger.flush()
    end)
  end
end
