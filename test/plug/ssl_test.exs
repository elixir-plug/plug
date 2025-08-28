defmodule Plug.SSLTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  setup_all do
    tmp_dir = System.tmp_dir!()
    certs_dir = Path.join(tmp_dir, "plug_ssl_test_certs_#{System.unique_integer()}")
    cert_path = Path.join(certs_dir, "cert.pem")
    key_path = Path.join(certs_dir, "key.pem")

    if System.find_executable("openssl") do
      File.mkdir_p!(certs_dir)

      args = [
        "req",
        "-x509",
        "-nodes",
        "-newkey",
        "rsa:2048",
        "-keyout",
        key_path,
        "-out",
        cert_path,
        "-days",
        "1",
        "-subj",
        "/CN=localhost"
      ]

      case System.cmd("openssl", args, stderr_to_stdout: true) do
        {_, 0} -> :ok
        {output, code} -> flunk("Failed to generate certs with openssl (#{code}): #{output}")
      end

      on_exit(fn -> File.rm_rf!(certs_dir) end)

      %{skip?: false, cert_path: cert_path, key_path: key_path}
    else
      Mix.shell().info(
        "[:warn] Skipping Plug.SSL certificate tests because `openssl` is not in PATH."
      )
      %{skip?: true, cert_path: nil, key_path: nil}
    end
  end


  describe "configure" do
    import Plug.SSL, only: [configure: 1]
    # make sure some dummy files used for the keyfile and certfile
    # tests are removed after each test.
        setup do
      app_dir = Application.app_dir(:plug)
      File.mkdir_p!(app_dir)
      key_path_dummy = Path.join(app_dir, "abcdef")
      cert_path_dummy = Path.join(app_dir, "ghijkl")
      File.touch!(key_path_dummy)
      File.touch!(cert_path_dummy)

      on_exit(fn ->
        File.rm(key_path_dummy)
        File.rm(cert_path_dummy)
      end)

      :ok
        end

    test "sets secure_renegotiate and reuse_sessions to true depending on the version", context do
      unless context.skip? do
        opts = [certfile: context.cert_path, keyfile: context.key_path, versions: [:tlsv1]]
        assert {:ok, opts} = configure(opts)
        assert opts[:reuse_sessions] == true
        assert opts[:secure_renegotiate] == true
        assert opts[:honor_cipher_order] == nil
        assert opts[:client_renegotiation] == nil
        assert opts[:cipher_suite] == nil

        opts = [certfile: context.cert_path, keyfile: context.key_path, versions: [:"tlsv1.3"]]
        assert {:ok, opts} = configure(opts)
        assert opts[:reuse_sessions] == nil
        assert opts[:secure_renegotiate] == nil
        assert opts[:honor_cipher_order] == nil
        assert opts[:client_renegotiation] == nil
        assert opts[:cipher_suite] == nil

        opts = [
          certfile: context.cert_path,
          keyfile: context.key_path,
          reuse_sessions: false
        ]

        assert {:ok, opts} = configure(opts)
        assert opts[:reuse_sessions] == false
      end
    end

    test "sets cipher suite to strong", context do
      unless context.skip? do
        opts = [
          certfile: context.cert_path,
          keyfile: context.key_path,
          cipher_suite: :strong
        ]

        assert {:ok, opts} = configure(opts)
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
    end

    test "sets cipher suite to compatible", context do
      unless context.skip? do
        opts = [
          certfile: context.cert_path,
          keyfile: context.key_path,
          cipher_suite: :compatible
        ]

        assert {:ok, opts} = configure(opts)
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
    end

    test "sets cipher suite with overrides compatible", context do
      unless context.skip? do
        assert {:ok, opts} =
                 configure(
                   keyfile: context.key_path,
                   certfile: context.cert_path,
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
    end

    test "allows bare atom configuration through unchanged", context do
      unless context.skip? do
        assert {:ok, opts} =
                 configure([
                   :inet6,
                   {:keyfile, context.key_path},
                   {:certfile, context.cert_path}
                 ])

        assert :inet6 in opts
        assert {:keyfile, to_charlist(context.key_path)} in opts
        assert {:certfile, to_charlist(context.cert_path)} in opts
      end
    end

    test "fails to configure if keyfile and certfile aren't absolute paths and otp_app is missing" do
      assert {:error, message} = configure([:inet6, keyfile: "abcdef", certfile: "ghijkl"])
      assert message == "the :otp_app option is required when setting relative SSL certfiles"
    end

    test "fails to configure if the keyfile doesn't exist" do
      assert {:error, message} =
               configure([:inet6, keyfile: "nonexistent", certfile: "nonexistent", otp_app: :plug])

      assert message =~
               ":keyfile either does not exist, or the application does not have permission to access it"
    end

    test "expands the paths to the keyfile and certfile using the otp_app", context do
      unless context.skip? do
        dir = Path.dirname(context.cert_path)
        File.mkdir_p!(dir)
        File.touch!(Path.join(dir, "abcdef"))
        File.touch!(Path.join(dir, "ghijkl"))

        assert {:ok, opts} =
                 configure([
                   :inet6,
                   keyfile: "abcdef",
                   certfile: "ghijkl",
                   otp_app: :plug
                 ])

        assert to_string(opts[:keyfile]) =~ "abcdef"
        assert to_string(opts[:certfile]) =~ "ghijkl"
      end
    end

    test "errors when an invalid cipher is given", context do
      unless context.skip? do
        assert configure(
                 keyfile: context.key_path,
                 certfile: context.cert_path,
                 cipher_suite: :unknown
               ) ==
                 {:error, "unknown :cipher_suite named :unknown"}
      end
    end

    test "errors when a cipher is provided as a binary string", context do
      unless context.skip? do
        assert {:error, message} =
                 configure(
                   keyfile: context.key_path,
                   certfile: context.cert_path,
                   ciphers: [~c"ECDHE-ECDSA-AES256-GCM-SHA384", "ECDHE-RSA-AES256-GCM-SHA384"]
                 )

        assert message ==
                 "invalid cipher \"ECDHE-RSA-AES256-GCM-SHA384\" in cipher list. " <>
                   "Strings (double-quoted) are not allowed in ciphers. " <>
                   "Ciphers must be either charlists (single-quoted) or tuples. " <>
                   "See the ssl application docs for reference"
      end
    end
  end

  def excluded_host?(host) do
    host == System.get_env("EXCLUDED_HOST")
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

    test "excludes tuple" do
      System.put_env("EXCLUDED_HOST", "10.0.0.1")

      conn =
        conn(:get, "https://10.0.0.1/")
        |> call(exclude: {__MODULE__, :excluded_host?, []})

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
