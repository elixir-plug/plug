defmodule Plug.Conn.WrapperErrorTest do
  use ExUnit.Case, async: true
  use Plug.Test

  test "reraise/3" do
    conn = conn(:get, "/")
    err  = RuntimeError.exception("hello")
    wrap = catch_error(Plug.Conn.WrapperError.reraise(conn, :error, err))
    assert wrap.conn == conn
    assert wrap.kind == :error
    assert wrap.reason == err
    assert wrap.stack == System.stacktrace
    assert catch_error(Plug.Conn.WrapperError.reraise(:whatever, :error, wrap)) == wrap
  end

  test "reraise/3 does not change exits or throws" do
    assert catch_throw(Plug.Conn.WrapperError.reraise(conn(:get, "/"), :throw, :oops)) == :oops
    assert catch_exit(Plug.Conn.WrapperError.reraise(conn(:get, "/"), :exit, :oops)) == :oops
  end
end
