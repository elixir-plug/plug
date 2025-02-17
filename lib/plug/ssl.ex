defmodule Plug.SSL do
  @moduledoc """
  A plug to force SSL connections and enable HSTS.

  If the scheme of a request is `https`, it'll add a `strict-transport-security`
  header to enable HTTP Strict Transport Security by default.

  Otherwise, the request will be redirected to a corresponding location
  with the `https` scheme by setting the `location` header of the response.
  The status code will be 301 if the method of `conn` is `GET` or `HEAD`,
  or 307 in other situations.

  Besides being a Plug, this module also provides conveniences for configuring
  SSL. See `configure/1`.

  ## x-forwarded-*

  If your Plug application is behind a proxy that handles HTTPS, you may
  need to tell Plug to parse the proper protocol from the `x-forwarded-*`
  header. This can be done using the `:rewrite_on` option:

      plug Plug.SSL, rewrite_on: [:x_forwarded_host, :x_forwarded_port, :x_forwarded_proto]

  Rewriting happens on all requests, before the SSL options are processed.
  For further details, refer to `Plug.RewriteOn`.

  ## Plug Options

    * `:rewrite_on` - rewrites the given connection information based on the given headers
    * `:hsts` - a boolean on enabling HSTS or not, defaults to `true`
    * `:expires` - seconds to expires for HSTS, defaults to `31_536_000` (1 year)
    * `:preload` - a boolean to request inclusion on the HSTS preload list
      (for full set of required flags, see: [Chromium HSTS submission site](https://hstspreload.org)),
      defaults to `false`
    * `:subdomains` - a boolean on including subdomains or not in HSTS,
      defaults to `false`
    * `:exclude` - exclude the given hosts from redirecting to the `https`
      scheme. Defaults to `["localhost"]`. It may be set to a list of binaries
      or a tuple [`{module, function, args}`](#module-excluded-hosts-tuple).
    * `:host` - a new host to redirect to if the request's scheme is `http`,
      defaults to `conn.host`. It may be set to a binary or a tuple
      `{module, function, args}` that will be invoked on demand
    * `:log` - The log level at which this plug should log its request info.
      Default is `:info`. Can be `false` to disable logging.

  ## Port

  It is not possible to directly configure the port in `Plug.SSL` because
  HSTS expects the port to be 443 for SSL. If you are not using HSTS and
  want to redirect to HTTPS on another port, you can sneak it alongside
  the host, for example: `host: "example.com:443"`.

  ## Excluded hosts tuple

  Tuple `{module, function, args}` can be passed to be invoked each time
  the plug is checking whether to redirect host. Provided function needs
  to receive at least one argument (`host`).

  For example, you may define it as:

      plug Plug.SSL,
        rewrite_on: [:x_forwarded_proto],
        exclude: {__MODULE__, :excluded_host?, []}

  where:

      def excluded_host?(host) do
        # Custom logic
      end

  """
  @behaviour Plug

  require Logger
  import Plug.Conn

  @strong_tls_ciphers [
    ~c"ECDHE-RSA-AES256-GCM-SHA384",
    ~c"ECDHE-ECDSA-AES256-GCM-SHA384",
    ~c"ECDHE-RSA-AES128-GCM-SHA256",
    ~c"ECDHE-ECDSA-AES128-GCM-SHA256",
    ~c"DHE-RSA-AES256-GCM-SHA384",
    ~c"DHE-RSA-AES128-GCM-SHA256"
  ]

  @compatible_tls_ciphers [
    ~c"ECDHE-RSA-AES256-GCM-SHA384",
    ~c"ECDHE-ECDSA-AES256-GCM-SHA384",
    ~c"ECDHE-RSA-AES128-GCM-SHA256",
    ~c"ECDHE-ECDSA-AES128-GCM-SHA256",
    ~c"DHE-RSA-AES256-GCM-SHA384",
    ~c"DHE-RSA-AES128-GCM-SHA256",
    ~c"ECDHE-RSA-AES256-SHA384",
    ~c"ECDHE-ECDSA-AES256-SHA384",
    ~c"ECDHE-RSA-AES128-SHA256",
    ~c"ECDHE-ECDSA-AES128-SHA256",
    ~c"DHE-RSA-AES256-SHA256",
    ~c"DHE-RSA-AES128-SHA256",
    ~c"ECDHE-RSA-AES256-SHA",
    ~c"ECDHE-ECDSA-AES256-SHA",
    ~c"ECDHE-RSA-AES128-SHA",
    ~c"ECDHE-ECDSA-AES128-SHA"
  ]

  @eccs [
    :secp256r1,
    :secp384r1,
    :secp521r1
  ]

  @doc """
  Configures and validates the options given to the `:ssl` application.

  This function is often called internally by adapters, such as Cowboy,
  to validate and set reasonable defaults for SSL handling. Therefore
  Plug users are not expected to invoke it directly, rather you pass
  the relevant SSL options to your adapter which then invokes this.

  ## Options

  This function accepts all options defined
  [in Erlang/OTP `:ssl` documentation](http://erlang.org/doc/man/ssl.html).

  Besides the options from `:ssl`, this function adds on extra option:

    * `:cipher_suite` - it may be `:strong` or `:compatible`,
      as outlined in the following section

  Furthermore, it sets the following defaults:

    * `secure_renegotiate: true` - to avoid certain types of man-in-the-middle attacks
    * `reuse_sessions: true` - for improved handshake performance of recurring connections

  For a complete guide on HTTPS and best pratices, see [our Plug HTTPS Guide](https.html).

  ## Cipher Suites

  To simplify configuration of TLS defaults, this function provides two preconfigured
  options: `cipher_suite: :strong` and `cipher_suite: :compatible`. The Ciphers
  chosen and related configuration come from the [OWASP Cipher String Cheat
  Sheet](https://www.owasp.org/index.php/TLS_Cipher_String_Cheat_Sheet)

  We've made two modifications to the suggested config from the OWASP recommendations.
  First we include ECDSA certificates which are excluded from their configuration.
  Second we have changed the order of the ciphers to deprioritize DHE because of
  performance implications noted within the OWASP post itself. As the article notes
  "...the TLS handshake with DHE hinders the CPU about 2.4 times more than ECDHE".

  The **Strong** cipher suite only supports tlsv1.2. Ciphers were based on the OWASP
  Group A+ and includes support for RSA or ECDSA certificates. The intention of this
  configuration is to provide as secure as possible defaults knowing that it will not
  be fully compatible with older browsers and operating systems.

  The **Compatible** cipher suite supports tlsv1, tlsv1.1 and tlsv1.2. Ciphers were
  based on the OWASP Group B and includes support for RSA or ECDSA certificates. The
  intention of this configuration is to provide as secure as possible defaults that
  still maintain support for older browsers and Android versions 4.3 and earlier

  For both suites we've specified certificate curves secp256r1, ecp384r1 and secp521r1.
  Since OWASP doesn't prescribe curves we've based the selection on [Mozilla's
  recommendations](https://wiki.mozilla.org/Security/Server_Side_TLS#Cipher_names_correspondence_table)

  **The cipher suites were last updated on 2018-JUN-14.**
  """
  @spec configure([:ssl.tls_server_option()]) ::
          {:ok, [:ssl.tls_server_option()]} | {:error, String.t()}
  def configure(options) do
    options
    |> check_for_missing_keys()
    |> validate_ciphers()
    |> normalize_ssl_files()
    |> normalize_certs_keys_ssl_files()
    |> convert_to_charlist()
    |> set_secure_defaults()
    |> configure_managed_tls()
  catch
    {:configure, message} -> {:error, message}
  else
    options -> {:ok, options}
  end

  defp check_for_missing_keys(options) do
    has_certs_keys? = List.keymember?(options, :certs_keys, 0)
    has_sni? = List.keymember?(options, :sni_hosts, 0) or List.keymember?(options, :sni_fun, 0)
    has_key? = List.keymember?(options, :key, 0) or List.keymember?(options, :keyfile, 0)
    has_cert? = List.keymember?(options, :cert, 0) or List.keymember?(options, :certfile, 0)

    cond do
      has_sni? -> options
      not (has_key? or has_certs_keys?) -> fail("missing option :key/:keyfile/:certs_keys")
      not (has_cert? or has_certs_keys?) -> fail("missing option :cert/:certfile/:certs_keys")
      true -> options
    end
  end

  defp normalize_ssl_files(options) do
    ssl_files = [:keyfile, :certfile, :cacertfile, :dhfile]
    Enum.reduce(ssl_files, options, &normalize_ssl_file(&1, &2, options[:otp_app]))
  end

  defp normalize_certs_keys_ssl_files(options) do
    if certs_keys = options[:certs_keys] do
      ssl_files = [:keyfile, :certfile]

      updated_certs_keys =
        Enum.map(certs_keys, fn cert_key ->
          Enum.reduce(
            ssl_files,
            Map.to_list(cert_key),
            &normalize_ssl_file(&1, &2, options[:otp_app])
          )
          |> Map.new()
        end)

      List.keystore(options, :certs_keys, 0, {:certs_keys, updated_certs_keys})
    else
      options
    end
  end

  defp normalize_ssl_file(key, options, otp_app) do
    value = options[key]

    cond do
      is_nil(value) ->
        options

      Path.type(value) == :absolute ->
        put_ssl_file(options, key, value)

      true ->
        put_ssl_file(options, key, Path.expand(value, resolve_otp_app(otp_app)))
    end
  end

  defp put_ssl_file(options, key, value) do
    value = to_charlist(value)

    unless File.exists?(value) do
      message =
        "the file #{value} required by SSL's #{inspect(key)} either does not exist, " <>
          "or the application does not have permission to access it"

      fail(message)
    end

    List.keystore(options, key, 0, {key, value})
  end

  defp resolve_otp_app(otp_app) do
    if otp_app do
      Application.app_dir(otp_app)
    else
      fail("the :otp_app option is required when setting relative SSL certfiles")
    end
  end

  defp convert_to_charlist(options) do
    Enum.reduce([:password], options, fn key, acc ->
      if value = acc[key] do
        List.keystore(acc, key, 0, {key, to_charlist(value)})
      else
        acc
      end
    end)
  end

  defp set_secure_defaults(options) do
    versions = options[:versions] || :ssl.versions()[:supported]

    if Enum.any?([:tlsv1, :"tlsv1.1", :"tlsv1.2"], &(&1 in versions)) do
      options
      |> keynew(:secure_renegotiate, 0, {:secure_renegotiate, true})
      |> keynew(:reuse_sessions, 0, {:reuse_sessions, true})
    else
      options
      |> List.keydelete(:secure_renegotiate, 0)
      |> List.keydelete(:reuse_sessions, 0)
    end
  end

  defp configure_managed_tls(options) do
    {_, cipher_suite} = List.keyfind(options, :cipher_suite, 0, {:cipher_suite, nil})
    options = List.keydelete(options, :cipher_suite, 0)

    case cipher_suite do
      :strong -> set_strong_tls_defaults(options)
      :compatible -> set_compatible_tls_defaults(options)
      nil -> options
      _ -> fail("unknown :cipher_suite named #{inspect(cipher_suite)}")
    end
  end

  defp set_managed_tls_defaults(options) do
    options
    |> keynew(:honor_cipher_order, 0, {:honor_cipher_order, true})
    |> keynew(:eccs, 0, {:eccs, @eccs})
  end

  defp set_strong_tls_defaults(options) do
    options
    |> set_managed_tls_defaults
    |> keynew(:ciphers, 0, {:ciphers, @strong_tls_ciphers})
    |> keynew(:versions, 0, {:versions, [:"tlsv1.2"]})
  end

  defp set_compatible_tls_defaults(options) do
    options
    |> set_managed_tls_defaults
    |> keynew(:ciphers, 0, {:ciphers, @compatible_tls_ciphers})
    |> keynew(:versions, 0, {:versions, [:"tlsv1.2", :"tlsv1.1", :tlsv1]})
  end

  defp validate_ciphers(options) do
    options
    |> List.keyfind(:ciphers, 0, {:ciphers, []})
    |> elem(1)
    |> Enum.each(&validate_cipher/1)

    options
  end

  defp validate_cipher(cipher) do
    if is_binary(cipher) do
      message =
        "invalid cipher #{inspect(cipher)} in cipher list. " <>
          "Strings (double-quoted) are not allowed in ciphers. " <>
          "Ciphers must be either charlists (single-quoted) or tuples. " <>
          "See the ssl application docs for reference"

      fail(message)
    end
  end

  defp fail(message) when is_binary(message) do
    throw({:configure, message})
  end

  defp keynew(list, key, position, value) do
    if List.keymember?(list, key, position), do: list, else: [value | list]
  end

  @impl true
  def init(opts) do
    host = Keyword.get(opts, :host)

    case host do
      {:system, _} ->
        IO.warn(
          "Using {:system, host} as your Plug.SSL host is deprecated. Pass nil or a string instead."
        )

      _ ->
        :ok
    end

    rewrite_on = Plug.RewriteOn.init(Keyword.get(opts, :rewrite_on))
    log = Keyword.get(opts, :log, :info)
    exclude = Keyword.get(opts, :exclude, ["localhost"])
    {hsts_header(opts), exclude, host, rewrite_on, log}
  end

  @impl true
  def call(conn, {hsts, exclude, host, rewrite_on, log_level}) do
    conn = Plug.RewriteOn.call(conn, rewrite_on)

    cond do
      excluded?(conn.host, exclude) -> conn
      conn.scheme == :https -> put_hsts_header(conn, hsts)
      true -> redirect_to_https(conn, host, log_level)
    end
  end

  defp excluded?(host, list) when is_list(list), do: :lists.member(host, list)
  defp excluded?(host, {mod, fun, args}), do: apply(mod, fun, [host | args])

  # http://tools.ietf.org/html/draft-hodges-strict-transport-sec-02
  defp hsts_header(opts) do
    if Keyword.get(opts, :hsts, true) do
      expires = Keyword.get(opts, :expires, 31_536_000)
      preload = Keyword.get(opts, :preload, false)
      subdomains = Keyword.get(opts, :subdomains, false)

      "max-age=#{expires}" <>
        if(preload, do: "; preload", else: "") <>
        if(subdomains, do: "; includeSubDomains", else: "")
    end
  end

  defp put_hsts_header(conn, hsts_header) when is_binary(hsts_header) do
    put_resp_header(conn, "strict-transport-security", hsts_header)
  end

  defp put_hsts_header(conn, nil), do: conn

  defp redirect_to_https(%{host: host} = conn, custom_host, log_level) do
    status = if conn.method in ~w(HEAD GET), do: 301, else: 307

    scheme_and_host = "https://" <> host(custom_host, host)
    location = scheme_and_host <> conn.request_path <> qs(conn.query_string)

    log_level &&
      Logger.log(log_level, fn ->
        [
          "Plug.SSL is redirecting ",
          conn.method,
          ?\s,
          conn.request_path,
          " to ",
          scheme_and_host,
          " with status ",
          Integer.to_string(status)
        ]
      end)

    conn
    |> put_resp_header("location", location)
    |> send_resp(status, "")
    |> halt
  end

  defp host(nil, host), do: host
  defp host(host, _) when is_binary(host), do: host
  defp host({mod, fun, args}, host), do: host(apply(mod, fun, args), host)
  # TODO: Remove me once the deprecation is removed.
  defp host({:system, env}, host), do: host(System.get_env(env), host)

  defp qs(""), do: ""
  defp qs(qs), do: "?" <> qs
end
