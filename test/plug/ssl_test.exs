defmodule Plug.SSLTest do
  use ExUnit.Case, async: true
  use Plug.Test

  defmodule MyPlug do
    use Plug.Builder

    plug Plug.SSL
    plug :passthrough

    defp passthrough(conn, _) do
      Plug.Conn.send_resp(conn, 200, "Passthrough")
    end
  end

  defp call(conn), do: MyPlug.call(conn, [])

  defp ssl_call(conn, opts) do
    Plug.SSL.call(conn, opts) |> Plug.Conn.send_resp(200, "Passthrough")
  end

  test "hsts headers by default" do
    conn = conn(:get, "https://example.com/") |> call
    assert List.keyfind(conn.resp_headers, "strict-transport-security", 0) ==
           {"strict-transport-security", "max-age=31536000"}
  end

  test "no hsts with insecure connection" do
    conn = conn(:get, "http://example.com/") |> call
    assert List.keyfind(conn.resp_headers, "strict-transport-security", 0) == nil
  end

  test "hsts is true" do
    opts = Plug.SSL.init(hsts: true)
    conn = conn(:get, "https://example.com/") |> ssl_call(opts)
    assert List.keyfind(conn.resp_headers, "strict-transport-security", 0) ==
           {"strict-transport-security", "max-age=31536000"}
  end

  test "hsts is false" do
    opts = Plug.SSL.init(hsts: false)
    conn = conn(:get, "https://example.com/") |> ssl_call(opts)
    assert List.keyfind(conn.resp_headers, "strict-transport-security", 0) == nil
  end

  test "hsts custom expires" do
    opts = Plug.SSL.init(expires: 3600)
    conn = conn(:get, "https://example.com/") |> ssl_call(opts)
    assert List.keyfind(conn.resp_headers, "strict-transport-security", 0) ==
           {"strict-transport-security", "max-age=3600"}
  end

  test "hsts include subdomains" do
    opts = Plug.SSL.init(subdomains: true)
    conn = conn(:get, "https://example.com/") |> ssl_call(opts)
    assert List.keyfind(conn.resp_headers, "strict-transport-security", 0) ==
           {"strict-transport-security", "max-age=31536000; includeSubDomains"}
  end

  test "redirect http to https" do
    conn = conn(:get, "http://example.com/path?q=foo&k=bar") |> call
    assert List.keyfind(conn.resp_headers, "location", 0) ==
           {"location", "https://example.com/path?q=foo&k=bar"}
    assert conn.status == 301
  end

  test "redirect to custom host" do
    opts = Plug.SSL.init(host: "ssl.example.com:443")
    conn = conn(:get, "http://example.com/") |> Plug.SSL.call(opts)
    assert List.keyfind(conn.resp_headers, "location", 0) ==
           {"location", "https://ssl.example.com:443/?"}
  end

  test "redirect status for head" do
    conn = conn(:head, "http://example.com/") |> call
    assert conn.status == 301
  end

  test "redirect status for other methods resulting in 307" do
    methods = ~w(options post put delete patch)a
    statuses = Enum.map methods, fn (method)->
      conn = conn(method, "http://example.com/") |> call
      conn.status
    end
    assert statuses == [307, 307, 307, 307, 307]
  end
end
