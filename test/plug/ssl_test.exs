defmodule Plug.SSLTest do
  use ExUnit.Case, async: true
  use Plug.Test

  defp call(conn, opts \\ []) do
    Plug.SSL.call(conn, Plug.SSL.init(opts))
  end

  test "hsts headers by default" do
    conn = conn(:get, "https://example.com/") |> call
    assert get_resp_header(conn, "strict-transport-security") ==
           ["max-age=31536000"]
    refute conn.halted
  end

  test "hsts is true" do
    conn = conn(:get, "https://example.com/") |> call(hsts: true)
    assert get_resp_header(conn, "strict-transport-security") ==
           ["max-age=31536000"]
    refute conn.halted
  end

  test "hsts is false" do
    conn = conn(:get, "https://example.com/") |> call(hsts: false)
    assert get_resp_header(conn, "strict-transport-security") == []
    refute conn.halted
  end

  test "hsts custom expires" do
    conn = conn(:get, "https://example.com/") |> call(expires: 3600)
    assert get_resp_header(conn, "strict-transport-security") ==
           ["max-age=3600"]
    refute conn.halted
  end

  test "hsts include subdomains" do
    conn = conn(:get, "https://example.com/") |> call(subdomains: true)
    assert get_resp_header(conn, "strict-transport-security") ==
           ["max-age=31536000; includeSubDomains"]
    refute conn.halted
  end

  test "rewrites conn http to https based on x-forwarded-proto" do
    conn = conn(:get, "http://example.com/")
           |> put_req_header("x-forwarded-proto", "https")
           |> call(rewrite_on: [:x_forwarded_proto])
    assert get_resp_header(conn, "strict-transport-security") ==
           ["max-age=31536000"]
    refute conn.halted
  end

  test "redirects to host when insecure" do
    conn = conn(:get, "http://example.com/") |> call()
    assert get_resp_header(conn, "location") ==
           ["https://example.com/"]
    assert conn.halted

    conn = conn(:get, "http://example.com/foo?bar=baz") |> call()
    assert get_resp_header(conn, "location") ==
           ["https://example.com/foo?bar=baz"]
    assert conn.halted
  end

  test "redirects to custom host on get" do
    conn = conn(:get, "http://example.com/")
           |> call(host: "ssl.example.com:443")
    assert get_resp_header(conn, "location") ==
           ["https://ssl.example.com:443/"]
    assert conn.status == 301
    assert conn.halted
  end

  test "redirects to environment host on get" do
    System.put_env("PLUG_SSL_HOST", "ssl.example.com:443")
    conn = conn(:get, "http://example.com/")
           |> call(host: {:system, "PLUG_SSL_HOST"})
    assert get_resp_header(conn, "location") ==
           ["https://ssl.example.com:443/"]
    assert conn.status == 301
    assert conn.halted
  end

  test "redirects to host on head" do
    conn = conn(:head, "http://example.com/") |> call
    assert conn.status == 301
    assert conn.halted
  end

  test "redirects to custom host with other verbs" do
    for method <- ~w(options post put delete patch)a do
      conn = conn(method, "http://example.com/") |> call
      assert conn.status == 307
      assert conn.halted
    end
  end
end
