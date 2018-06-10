defmodule Plug.SSLTest do
  use ExUnit.Case, async: true
  use Plug.Test

  describe "configure" do
    import Plug.SSL, only: [configure: 1]

    test "sets secure_renegotiate and reuse_sessions to true by default" do
      assert {:ok, opts} = configure(key: "abcdef", cert: "ghijkl")
      assert opts[:reuse_sessions] == true
      assert opts[:secure_renegotiate] == true

      assert {:ok, opts} = configure(key: "abcdef", cert: "ghijkl", reuse_sessions: false)
      assert opts[:reuse_sessions] == false
    end
  end

  defp call(conn, opts \\ []) do
    opts = Keyword.put_new(opts, :log, false)
    Plug.SSL.call(conn, Plug.SSL.init(opts))
  end

  describe "HSTS" do
    test "includes headers by default" do
      conn = call(conn(:get, "https://example.com/"))
      assert get_resp_header(conn, "strict-transport-security") == ["max-age=31536000"]
      refute conn.halted
    end

    test "excludes localhost" do
      conn = call(conn(:get, "https://localhost/"))
      assert get_resp_header(conn, "strict-transport-security") == []
      refute conn.halted
    end

    test "excludes custom" do
      conn = call(conn(:get, "https://example.com/"), exclude: ["example.com"])
      assert get_resp_header(conn, "strict-transport-security") == []
      refute conn.halted
    end

    test "when true" do
      conn = call(conn(:get, "https://example.com/"), hsts: true)
      assert get_resp_header(conn, "strict-transport-security") == ["max-age=31536000"]
      refute conn.halted
    end

    test "when false" do
      conn = call(conn(:get, "https://example.com/"), hsts: false)
      assert get_resp_header(conn, "strict-transport-security") == []
      refute conn.halted
    end

    test "with custom expires" do
      conn = call(conn(:get, "https://example.com/"), expires: 3600)
      assert get_resp_header(conn, "strict-transport-security") == ["max-age=3600"]
      refute conn.halted
    end

    test "includes subdomains" do
      conn = call(conn(:get, "https://example.com/"), subdomains: true)

      assert get_resp_header(conn, "strict-transport-security") ==
               ["max-age=31536000; includeSubDomains"]

      refute conn.halted
    end

    test "includes preload" do
      conn = call(conn(:get, "https://example.com/"), preload: true)
      assert get_resp_header(conn, "strict-transport-security") == ["max-age=31536000; preload"]
      refute conn.halted
    end

    test "with multiple flags" do
      conn = call(conn(:get, "https://example.com/"), preload: true, subdomains: true)

      assert get_resp_header(conn, "strict-transport-security") ==
               ["max-age=31536000; preload; includeSubDomains"]

      refute conn.halted
    end
  end

  describe ":rewrite_on" do
    test "rewrites conn http to https based on x-forwarded-proto" do
      conn =
        conn(:get, "http://example.com/")
        |> put_req_header("x-forwarded-proto", "https")
        |> call(rewrite_on: [:x_forwarded_proto])

      assert get_resp_header(conn, "strict-transport-security") == ["max-age=31536000"]
      refute conn.halted
    end
  end

  describe "redirects" do
    test "to host when insecure" do
      conn = call(conn(:get, "http://example.com/"))
      assert get_resp_header(conn, "location") == ["https://example.com/"]
      assert conn.halted

      conn = call(conn(:get, "http://example.com/foo?bar=baz"))
      assert get_resp_header(conn, "location") == ["https://example.com/foo?bar=baz"]
      assert conn.halted
    end

    test "to host when secure" do
      conn =
        conn(:get, "https://example.com/")
        |> put_req_header("x-forwarded-proto", "http")
        |> call(rewrite_on: [:x_forwarded_proto])

      assert get_resp_header(conn, "location") == ["https://example.com/"]
      assert conn.halted

      conn =
        conn(:get, "https://example.com/foo?bar=baz")
        |> put_req_header("x-forwarded-proto", "http")
        |> call(rewrite_on: [:x_forwarded_proto])

      assert get_resp_header(conn, "location") == ["https://example.com/foo?bar=baz"]
      assert conn.halted
    end

    test "to custom host on get" do
      conn = call(conn(:get, "http://example.com/"), host: "ssl.example.com:443")
      assert get_resp_header(conn, "location") == ["https://ssl.example.com:443/"]
      assert conn.status == 301
      assert conn.halted
    end

    test "to tuple host on get" do
      System.put_env("PLUG_SSL_HOST", "ssl.example.com:443")
      conn = call(conn(:get, "http://example.com/"), host: {System, :get_env, ["PLUG_SSL_HOST"]})
      assert get_resp_header(conn, "location") == ["https://ssl.example.com:443/"]
      assert conn.status == 301
      assert conn.halted
    end

    test "to host on head" do
      conn = call(conn(:head, "http://example.com/"))
      assert conn.status == 301
      assert conn.halted
    end

    test "to custom host with other verbs" do
      for method <- ~w(options post put delete patch)a do
        conn = call(conn(method, "http://example.com/"))
        assert conn.status == 307
        assert conn.halted
      end
    end

    test "logs on redirect" do
      message =
        ExUnit.CaptureLog.capture_log(fn ->
          conn = call(conn(:get, "http://example.com/"), log: :info)
          assert get_resp_header(conn, "location") == ["https://example.com/"]
          assert conn.halted
        end)

      assert message =~ ~r"Plug.SSL is redirecting GET / to https://example.com with status 301"u
    end
  end
end
