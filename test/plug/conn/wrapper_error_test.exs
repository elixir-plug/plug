defmodule Plug.Conn.WrapperErrorTest do
  use ExUnit.Case, async: true
  use Plug.Test

  test "wrap/3" do
    conn = conn(:get, "/")
    err  = RuntimeError.exception("hello")
    wrap = catch_error(Plug.Conn.WrapperError.reraise(conn, :error, err))
    assert wrap.conn == conn
    assert wrap.kind == :error
    assert wrap.reason == err
    assert wrap.stack == System.stacktrace
    assert catch_error(Plug.Conn.WrapperError.reraise(:whatever, :error, wrap)) == wrap
  end
end
