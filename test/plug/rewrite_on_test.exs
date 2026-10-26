defmodule Plug.RewriteOnTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  defp call(conn, rewrite) do
    Plug.RewriteOn.call(conn, Plug.RewriteOn.init(rewrite))
  end

  test "rewrites http to https based on MFArgs" do
    conn =
      conn(:get, "http://example.com/")
      |> put_req_header("x-forwarded-proto", "https")
      |> call({List, :flatten, [[:x_forwarded_proto]]})

    assert conn.scheme == :https
    assert conn.port == 443
  end

  test "rewrites http to https based on x-forwarded-proto" do
    conn =
      conn(:get, "http://example.com/")
      |> put_req_header("x-forwarded-proto", "https")
      |> call(:x_forwarded_proto)

    assert conn.scheme == :https
    assert conn.port == 443
  end

  test "rewrites http to https based on a custom header" do
    conn =
      conn(:get, "http://example.com/")
      |> put_req_header("custom-forwarded-proto", "https")
      |> call({:scheme, "custom-forwarded-proto"})

    assert conn.scheme == :https
    assert conn.port == 443
  end

  test "rewrites http to https when x-forwarded-proto value wss" do
    conn =
      conn(:get, "http://example.com/")
      |> put_req_header("x-forwarded-proto", "wss")
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

  test "rewrites host with a x-forwarded-host header" do
    conn =
      conn(:get, "http://example.com/")
      |> put_req_header("x-forwarded-host", "truessl.example.com")
      |> call(:x_forwarded_host)

    assert conn.host == "truessl.example.com"
  end

  test "rewrites host and port with a x-forwarded-host header that has a port" do
    conn =
      conn(:get, "http://example.com/")
      |> put_req_header("x-forwarded-host", "truessl.example.com:8443")
      |> call(:x_forwarded_host)

    assert conn.host == "truessl.example.com"
    assert conn.port == 8443

    conn =
      conn(:get, "http://example.com/")
      |> put_req_header("x-forwarded-host", "[2001:db8::1]:8443")
      |> call(:x_forwarded_host)

    assert conn.host == "[2001:db8::1]"
    assert conn.port == 8443
  end

  test "rewrites only the host with a x-forwarded-host header without a valid port" do
    for host <- [
          "[2001:db8::1]",
          "2001:db8::1",
          "truessl.example.com:",
          "truessl.example.com:https"
        ] do
      conn =
        conn(:get, "http://example.com/")
        |> put_req_header("x-forwarded-host", host)
        |> call(:x_forwarded_host)

      assert conn.host == host
      assert conn.port == 80
    end
  end

  test "x-forwarded-port takes precedence over the port in x-forwarded-host" do
    conn =
      conn(:get, "http://example.com/")
      |> put_req_header("x-forwarded-host", "truessl.example.com:8443")
      |> put_req_header("x-forwarded-port", "9443")
      |> call([:x_forwarded_host, :x_forwarded_port])

    assert conn.host == "truessl.example.com"
    assert conn.port == 9443
  end

  test "rewrites host with a custom header" do
    conn =
      conn(:get, "http://example.com/")
      |> put_req_header("custom-forwarded-host", "truessl.example.com")
      |> call({:host, "custom-forwarded-host"})

    assert conn.host == "truessl.example.com"
  end

  test "rewrites port with a x-forwarded-port header" do
    conn =
      conn(:get, "http://example.com/")
      |> put_req_header("x-forwarded-port", "3030")
      |> call(:x_forwarded_port)

    assert conn.port == 3030
  end

  test "does not rewrite port with more than 5 bytes" do
    conn =
      conn(:get, "http://example.com/")
      |> put_req_header("x-forwarded-port", "303030")
      |> call(:x_forwarded_port)

    assert conn.port == 80
  end

  test "rewrites port with a custom header" do
    conn =
      conn(:get, "http://example.com/")
      |> put_req_header("custom-forwarded-port", "3030")
      |> call({:port, "custom-forwarded-port"})

    assert conn.port == 3030
  end

  test "rewrites remote_ip with a x-forwarded-for header" do
    conn =
      conn(:get, "http://example.com/")
      |> put_req_header("x-forwarded-for", "bad")
      |> call(:x_forwarded_for)

    assert conn.remote_ip == {127, 0, 0, 1}

    conn =
      conn(:get, "http://example.com/")
      |> put_req_header("x-forwarded-for", "4.3.2.1")
      |> call(:x_forwarded_for)

    assert conn.remote_ip == {4, 3, 2, 1}

    conn =
      conn(:get, "http://example.com/")
      |> put_req_header("x-forwarded-for", "1.2.3.4,::1")
      |> call(:x_forwarded_for)

    assert conn.remote_ip == {1, 2, 3, 4}

    conn =
      conn(:get, "http://example.com/")
      |> put_req_header("x-forwarded-for", "::1,1.2.3.4")
      |> call(:x_forwarded_for)

    assert conn.remote_ip == {0, 0, 0, 0, 0, 0, 0, 1}
  end

  test "rewrites remote_ip with a custom header" do
    conn =
      conn(:get, "http://example.com/")
      |> put_req_header("custom-forwarded-for", "bad")
      |> call({:remote_ip, "custom-forwarded-for"})

    assert conn.remote_ip == {127, 0, 0, 1}

    conn =
      conn(:get, "http://example.com/")
      |> put_req_header("custom-forwarded-for", "4.3.2.1")
      |> call({:remote_ip, "custom-forwarded-for"})

    assert conn.remote_ip == {4, 3, 2, 1}

    conn =
      conn(:get, "http://example.com/")
      |> put_req_header("custom-forwarded-for", "1.2.3.4,::1")
      |> call({:remote_ip, "custom-forwarded-for"})

    assert conn.remote_ip == {1, 2, 3, 4}

    conn =
      conn(:get, "http://example.com/")
      |> put_req_header("custom-forwarded-for", "::1,1.2.3.4")
      |> call({:remote_ip, "custom-forwarded-for"})

    assert conn.remote_ip == {0, 0, 0, 0, 0, 0, 0, 1}
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

  test "rewrites the host, the port, and the protocol with custom headers" do
    conn =
      conn(:get, "http://example.com/")
      |> put_req_header("custom-forwarded-host", "truessl.example.com")
      |> put_req_header("custom-forwarded-port", "3030")
      |> put_req_header("custom-forwarded-proto", "https")
      |> call(
        host: "custom-forwarded-host",
        port: "custom-forwarded-port",
        scheme: "custom-forwarded-proto"
      )

    assert conn.host == "truessl.example.com"
    assert conn.port == 3030
    assert conn.scheme == :https
  end

  test "raises when receiving an unknown rewrite" do
    assert_raise RuntimeError, "unknown rewrite: :x_forwarded_other", fn ->
      call(conn(:get, "http://example.com/"), :x_forwarded_other)
    end

    assert_raise RuntimeError, "unknown rewrite: {:other, \"value\"}", fn ->
      call(conn(:get, "http://example.com/"), other: "value")
    end
  end
end
