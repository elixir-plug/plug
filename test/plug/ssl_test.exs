defmodule Plug.SSLTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  describe "configure" do
    # make sure some dummy files used for the keyfile and certfile
    # tests are removed after each test.
    setup do
      on_exit(fn ->
        File.rm("_build/test/lib/plug/abcdef")
        File.rm("_build/test/lib/plug/ghijkl")
      end)

      []
    end

    import Plug.SSL, only: [configure: 1]

    test "sets secure_renegotiate and reuse_sessions to true depending on the version" do
      assert {:ok, opts} = configure(key: "abcdef", cert: "ghijkl", versions: [:tlsv1])
      assert opts[:reuse_sessions] == true
      assert opts[:secure_renegotiate] == true
      assert opts[:honor_cipher_order] == nil
      assert opts[:client_renegotiation] == nil
      assert opts[:cipher_suite] == nil

      assert {:ok, opts} = configure(key: "abcdef", cert: "ghijkl", versions: [:"tlsv1.3"])
      assert opts[:reuse_sessions] == nil
      assert opts[:secure_renegotiate] == nil
      assert opts[:honor_cipher_order] == nil
      assert opts[:client_renegotiation] == nil
      assert opts[:cipher_suite] == nil

      assert {:ok, opts} = configure(key: "abcdef", cert: "ghijkl", reuse_sessions: false)
      assert opts[:reuse_sessions] == false
    end

    test "sets cipher suite to strong" do
      assert {:ok, opts} = configure(key: "abcdef", cert: "ghijkl", cipher_suite: :strong)
      assert opts[:reuse_sessions] == nil
      assert opts[:secure_renegotiate] == nil
      assert opts[:cipher_suite] == nil
      assert opts[:honor_cipher_order] == true
      assert opts[:eccs] == [:x25519, :secp256r1, :secp384r1, :secp521r1]
      assert opts[:versions] == [:"tlsv1.3"]

      assert opts[:ciphers] == [
               ~c"TLS_AES_256_GCM_SHA384",
               ~c"TLS_CHACHA20_POLY1305_SHA256",
               ~c"TLS_AES_128_GCM_SHA256"
             ]
    end

    test "sets cipher suite to compatible" do
      assert {:ok, opts} = configure(key: "abcdef", cert: "ghijkl", cipher_suite: :compatible)
      assert opts[:reuse_sessions] == true
      assert opts[:secure_renegotiate] == true
      assert opts[:cipher_suite] == nil
      assert opts[:honor_cipher_order] == true
      assert opts[:eccs] == [:x25519, :secp256r1, :secp384r1, :secp521r1]
      assert opts[:versions] == [:"tlsv1.3", :"tlsv1.2"]

      assert opts[:ciphers] == [
               ~c"TLS_AES_256_GCM_SHA384",
               ~c"TLS_CHACHA20_POLY1305_SHA256",
               ~c"TLS_AES_128_GCM_SHA256",
               ~c"ECDHE-ECDSA-AES256-GCM-SHA384",
               ~c"ECDHE-RSA-AES256-GCM-SHA384",
               ~c"ECDHE-ECDSA-CHACHA20-POLY1305",
               ~c"ECDHE-RSA-CHACHA20-POLY1305",
               ~c"ECDHE-ECDSA-AES128-GCM-SHA256",
               ~c"ECDHE-RSA-AES128-GCM-SHA256",
               ~c"DHE-RSA-AES256-GCM-SHA384",
               ~c"DHE-RSA-AES128-GCM-SHA256"
             ]
    end

    test "sets cipher suite with overrides compatible" do
      assert {:ok, opts} =
               configure(
                 key: "abcdef",
                 cert: "ghijkl",
                 cipher_suite: :compatible,
                 ciphers: [],
                 client_renegotiation: true,
                 eccs: [],
                 versions: [],
                 honor_cipher_order: false
               )

      assert opts[:cipher_suite] == nil
      assert opts[:honor_cipher_order] == false
      assert opts[:client_renegotiation] == true
      assert opts[:eccs] == []
      assert opts[:versions] == []
      assert opts[:ciphers] == []
    end

    test "allows bare atom configuration through unchanged" do
      assert {:ok, opts} = configure([:inet6, {:key, "abcdef"}, {:cert, "ghijkl"}])
      assert :inet6 in opts
      assert {:key, "abcdef"} in opts
      assert {:cert, "ghijkl"} in opts
    end

    test "fails to configure if keyfile and certfile aren't absolute paths and otp_app is missing" do
      assert {:error, message} = configure([:inet6, keyfile: "abcdef", certfile: "ghijkl"])
      assert message == "the :otp_app option is required when setting relative SSL certfiles"
    end

    test "fails to configure if the keyfile doesn't exist" do
      assert {:error, message} =
               configure([:inet6, keyfile: "abcdef", certfile: "ghijkl", otp_app: :plug])

      assert message =~
               ":keyfile either does not exist, or the application does not have permission to access it"
    end

    test "fails to configure if the certfile doesn't exist" do
      File.touch("_build/test/lib/plug/abcdef")

      assert {:error, message} =
               configure([:inet6, keyfile: "abcdef", certfile: "ghijkl", otp_app: :plug])

      assert message =~
               ":certfile either does not exist, or the application does not have permission to access it"
    end

    test "expands the paths to the keyfile and certfile using the otp_app" do
      File.touch("_build/test/lib/plug/abcdef")
      File.touch("_build/test/lib/plug/ghijkl")

      assert {:ok, opts} =
               configure([:inet6, keyfile: "abcdef", certfile: "ghijkl", otp_app: :plug])

      assert to_string(opts[:keyfile]) =~ "_build/test/lib/plug/abcdef"
      assert to_string(opts[:certfile]) =~ "_build/test/lib/plug/ghijkl"
    end

    test "supports the certs_keys ssl config option" do
      assert {:ok, opts} =
               configure([:inet6, certs_keys: [%{key: "abcdef", cert: "ghijkl"}]])

      assert :inet6 in opts
      assert opts[:certs_keys] == [%{key: "abcdef", cert: "ghijkl"}]
    end

    test "expands the paths for keyfile and certfile in the certs_keys ssl config option" do
      File.touch("_build/test/lib/plug/abcdef")
      File.touch("_build/test/lib/plug/ghijkl")

      assert {:ok, opts} =
               configure([
                 :inet6,
                 certs_keys: [%{keyfile: "abcdef", certfile: "ghijkl"}],
                 otp_app: :plug
               ])

      assert :inet6 in opts

      [%{keyfile: keyfile, certfile: certfile}] = opts[:certs_keys]

      assert to_string(keyfile) =~ "_build/test/lib/plug/abcdef"
      assert to_string(certfile) =~ "_build/test/lib/plug/ghijkl"
    end

    test "errors when an invalid cipher is given" do
      assert configure(key: "abcdef", cert: "ghijkl", cipher_suite: :unknown) ==
               {:error, "unknown :cipher_suite named :unknown"}
    end

    test "errors when a cipher is provided as a binary string" do
      assert {:error, message} =
               configure(
                 key: "abcdef",
                 cert: "ghijkl",
                 ciphers: [~c"ECDHE-ECDSA-AES256-GCM-SHA384", "ECDHE-RSA-AES256-GCM-SHA384"]
               )

      assert message ==
               "invalid cipher \"ECDHE-RSA-AES256-GCM-SHA384\" in cipher list. " <>
                 "Strings (double-quoted) are not allowed in ciphers. " <>
                 "Ciphers must be either charlists (single-quoted) or tuples. " <>
                 "See the ssl application docs for reference"
    end
  end

  def excluded_host?(%Plug.Conn{} = conn, field),
    do: Map.fetch!(conn, field) == System.get_env("EXCLUDED_HOST")

  def excluded_host?(host) when is_binary(host),
    do: host == System.get_env("EXCLUDED_HOST")

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

  describe ":exclude" do
    test "excludes localhost by default" do
      conn = call(conn(:get, "https://localhost/"))
      assert get_resp_header(conn, "strict-transport-security") == []
      refute conn.halted
    end

    test "excludes hosts" do
      conn = call(conn(:get, "https://localhost.com/"), exclude: [hosts: ["example.com"]])
      assert get_resp_header(conn, "strict-transport-security") == ["max-age=31536000"]
      refute conn.halted

      conn = call(conn(:get, "https://example.com/"), exclude: [hosts: ["example.com"]])
      assert get_resp_header(conn, "strict-transport-security") == []
      refute conn.halted
    end

    test "excludes paths" do
      conn = call(conn(:get, "https://localhost/"), exclude: [paths: ["/health"]])
      assert get_resp_header(conn, "strict-transport-security") == ["max-age=31536000"]
      refute conn.halted

      conn = call(conn(:get, "https://localhost/health"), exclude: [paths: ["/health"]])
      assert get_resp_header(conn, "strict-transport-security") == []
      refute conn.halted
    end

    test "excludes conn mfargs" do
      System.put_env("EXCLUDED_HOST", "10.0.0.1")

      conn =
        call(conn(:get, "https://10.0.0.1/"),
          exclude: [conn: {__MODULE__, :excluded_host?, [:host]}]
        )

      assert get_resp_header(conn, "strict-transport-security") == []
      refute conn.halted
    end

    test "excludes deprecated binary" do
      conn = call(conn(:get, "https://example.com/"), exclude: ["example.com"])
      assert get_resp_header(conn, "strict-transport-security") == []
      refute conn.halted
    end

    test "excludes deprecated tuple" do
      System.put_env("EXCLUDED_HOST", "10.0.0.1")

      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        conn =
          conn(:get, "https://10.0.0.1/")
          |> call(exclude: {__MODULE__, :excluded_host?, []})

        assert get_resp_header(conn, "strict-transport-security") == []
        refute conn.halted
      end)
    end
  end

  describe ":rewrite_on" do
    test "rewrites http to https based on x-forwarded-proto" do
      conn =
        conn(:get, "http://example.com/")
        |> put_req_header("x-forwarded-proto", "https")
        |> call(rewrite_on: [:x_forwarded_proto])

      assert get_resp_header(conn, "strict-transport-security") == ["max-age=31536000"]
      assert conn.scheme == :https
      assert conn.port == 443
      refute conn.halted
    end

    test "doesn't change the port when it doesn't match the scheme" do
      conn =
        conn(:get, "http://example.com:1234/")
        |> put_req_header("x-forwarded-proto", "https")
        |> call(rewrite_on: [:x_forwarded_proto])

      assert conn.scheme == :https
      assert conn.port == 1234
      refute conn.halted
    end

    test "rewrites host with a x-forwarder-host header" do
      conn =
        conn(:get, "http://example.com/")
        |> put_req_header("x-forwarded-host", "truessl.example.com")
        |> call(rewrite_on: [:x_forwarded_host])

      assert conn.status == 301
      assert conn.host == "truessl.example.com"
      assert conn.halted
    end

    test "rewrites port with a x-forwarder-port header" do
      conn =
        conn(:get, "http://example.com/")
        |> put_req_header("x-forwarded-port", "3030")
        |> call(rewrite_on: [:x_forwarded_port])

      assert conn.status == 301
      assert conn.port == 3030
      assert conn.halted
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

    test "host have priority over rewrite_on option" do
      conn =
        conn(:get, "http://example.com/")
        |> put_req_header("x-forwarded-host", "truessl.example.com")
        |> call(rewrite_on: [:x_forwarded_host], host: "xyz.example.com")

      assert get_resp_header(conn, "location") == ["https://xyz.example.com/"]
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
