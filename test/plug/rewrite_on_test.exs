defmodule Plug.RewriteOnTest do
  use ExUnit.Case, async: true
  use Plug.Test

  defp call(conn, rewrite) do
    Plug.RewriteOn.call(conn, Plug.RewriteOn.init(rewrite))
  end

  test "rewrites http to https based on x-forwarded-proto" do
    conn =
      conn(:get, "http://example.com/")
      |> put_req_header("x-forwarded-proto", "https")
      |> call(:x_forwarded_proto)

    assert conn.scheme == :https
    assert conn.port == 443
  end

  test "doesn't change the port when it doesn't match the scheme" do
    conn =
      conn(:get, "http://example.com:1234/")
      |> put_req_header("x-forwarded-proto", "https")
      |> call(:x_forwarded_proto)

    assert conn.scheme == :https
    assert conn.port == 1234
  end

  test "rewrites host with a x-forwarder-host header" do
    conn =
      conn(:get, "http://example.com/")
      |> put_req_header("x-forwarded-host", "truessl.example.com")
      |> call(:x_forwarded_host)

    assert conn.host == "truessl.example.com"
  end

  test "rewrites port with a x-forwarder-port header" do
    conn =
      conn(:get, "http://example.com/")
      |> put_req_header("x-forwarded-port", "3030")
      |> call(:x_forwarded_port)

    assert conn.port == 3030
  end

  test "rewrites the host, the port, and the protocol" do
    conn =
      conn(:get, "http://example.com/")
      |> put_req_header("x-forwarded-host", "truessl.example.com")
      |> put_req_header("x-forwarded-port", "3030")
      |> put_req_header("x-forwarded-proto", "https")
      |> call([:x_forwarded_host, :x_forwarded_port, :x_forwarded_proto])

    assert conn.host == "truessl.example.com"
    assert conn.port == 3030
    assert conn.scheme == :https
  end

  test "raises when receiving an unknown rewrite" do
    assert_raise RuntimeError, "unknown rewrite: :x_forwarded_other", fn ->
      call(conn(:get, "http://example.com/"), :x_forwarded_other)
    end
  end
end
