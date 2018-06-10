defmodule Plug.SSL do
  @moduledoc """
  A plug to force SSL connections and enable HSTS.

  If the scheme of a request is `https`, it'll add a `strict-transport-security`
  header to enable HTTP Strict Transport Security by default.

  Otherwise, the request will be redirected to a corresponding location
  with the `https` scheme by setting the `location` header of the response.
  The status code will be 301 if the method of `conn` is `GET` or `HEAD`,
  or 307 in other situations.

  ## x-forwarded-proto

  If your Plug application is behind a proxy that handles HTTPS, you will
  need to tell Plug to parse the proper protocol from the `x-forwarded-proto`
  header. This can be done using the `:rewrite_on` option:

      plug Plug.SSL, rewrite_on: [:x_forwarded_proto]

  The command above will effectively change the value of `conn.scheme` by
  the one sent in `x-forwarded-proto`.

  Since rewriting the scheme based on `x-forwarded-proto` can open up
  security vulnerabilities, only provide the option above if:

    * your app is behind a proxy
    * your proxy strips `x-forwarded-proto` headers from all incoming requests
    * your proxy sets the `x-forwarded-proto` and sends it to Plug

  ## Options

    * `:rewrite_on` - rewrites the scheme to https based on the given headers
    * `:hsts` - a boolean on enabling HSTS or not, defaults to `true`
    * `:expires` - seconds to expires for HSTS, defaults to `7884000` (three months)
    * `:preload` - a boolean to request inclusion on the HSTS preload list
       (for full set of required flags, see: [Chromium HSTS submission site](https://hstspreload.org)),
      defaults to `false`
    * `:subdomains` - a boolean on including subdomains or not in HSTS,
      defaults to `false`
    * `:exclude` - exclude the given hosts from having HSTS applied to them.
      Defaults to `["localhost"]`
    * `:host` - a new host to redirect to if the request's scheme is `http`,
      defaults to `conn.host`. It may be set to a binary or a tuple
      `{module, function, args}` that will be invoked on demand
    * `:log` - The log level at which this plug should log its request info.
      Default is `:info`. Can be `false` to disable logging.

  ## Port

  It is not possible to directly configure the port in `Plug.SSL` because
  HSTS expects the port to be 443 for SSL. If you are not using HSTS and
  wants to redirect to HTTPS on another port, you can sneak it alongside
  the host, for example: `host: "example.com:443"`.
  """
  @behaviour Plug

  require Logger
  import Plug.Conn

  @doc """
  Configures and validates the options given to the `:ssl` application.

  This function is often called internally by adapters, such as Cowboy,
  to validate and set reasonable defaults for SSL handling. Therefore
  Plug users are not expected to invoke it directly, rather you pass
  the relevant SSL options to your adapter which then invokes this.

  For instance, here is how you would pass the SSL options to the Cowboy
  adapter:

      Plug.Adapters.Cowboy2.https MyPlug, [],
        port: 443,
        password: "SECRET",
        otp_app: :my_app,
        keyfile: "priv/ssl/key.pem",
        certfile: "priv/ssl/cert.pem",
        dhfile: "priv/ssl/dhparam.pem"

  or using the new child spec API:

      {Plug.Adapters.Cowboy2, scheme: :https, plug: MyPlug, options: [
         port: 443,
         password: "SECRET",
         otp_app: :my_app,
         keyfile: "priv/ssl/key.pem",
         certfile: "priv/ssl/cert.pem",
         dhfile: "priv/ssl/dhparam.pem"
       ]}

  ## Options

  This function accepts and validates all options defined in [the `ssl`
  erlang module](http://www.erlang.org/doc/man/ssl.html). With the
  following additions:

    * The certificate files, like keyfile, certfile, cacertfile, dhfile
      can be given as a relative path. For such, the `:otp_app` option
      must also be given and certificates will be looked from the priv
      directory of the given application

    * In order to provide better security, this function also sets
      safer defaults for certain options. See the "Defaults" section
      below

  ## Defaults

  This function sets the following defaults:

    * `:reuse_sessions` is set to true to instruct clients to reuse sessions
      when possible
    * `:secure_renegotiate` is set to true to enforce secure renegotiation
      according to RFC 5746

  """
  @spec configure(Keyword.t()) :: {:ok, Keyword.t()} | {:error, String.t()}
  def configure(options) do
    options
    |> check_for_missing_keys()
    |> normalize_ssl_files()
    |> convert_to_charlist()
    |> set_secure_defaults()
  catch
    {:configure, message} -> {:error, message}
  else
    options -> {:ok, options}
  end

  defp check_for_missing_keys(options) do
    has_sni? = Keyword.has_key?(options, :sni_hosts) or Keyword.has_key?(options, :sni_fun)
    has_key? = Keyword.has_key?(options, :key) or Keyword.has_key?(options, :keyfile)
    has_cert? = Keyword.has_key?(options, :cert) or Keyword.has_key?(options, :certfile)

    cond do
      has_sni? -> options
      not has_key? -> fail("missing option :key/:keyfile")
      not has_cert? -> fail("missing option :cert/:certfile")
      true -> options
    end
  end

  defp normalize_ssl_files(options) do
    ssl_files = [:keyfile, :certfile, :cacertfile, :dhfile]
    Enum.reduce(ssl_files, options, &normalize_ssl_file(&1, &2))
  end

  defp normalize_ssl_file(key, options) do
    value = options[key]

    cond do
      is_nil(value) ->
        options

      Path.type(value) == :absolute ->
        put_ssl_file(options, key, value)

      true ->
        put_ssl_file(options, key, Path.expand(value, otp_app(options)))
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

    Keyword.put(options, key, value)
  end

  defp otp_app(options) do
    if app = options[:otp_app] do
      Application.app_dir(app)
    else
      fail("the :otp_app option is required when setting relative SSL certfiles")
    end
  end

  defp convert_to_charlist(options) do
    Enum.reduce([:password], options, fn key, acc ->
      if value = acc[key] do
        Keyword.put(acc, key, to_charlist(value))
      else
        acc
      end
    end)
  end

  defp set_secure_defaults(options) do
    options
    |> Keyword.put_new(:secure_renegotiate, true)
    |> Keyword.put_new(:reuse_sessions, true)
  end

  defp fail(message) when is_binary(message) do
    throw({:configure, message})
  end

  @doc """
  Plug initialization callback.
  """
  def init(opts) do
    host = Keyword.get(opts, :host)
    rewrite_on = Keyword.get(opts, :rewrite_on, [])
    log = Keyword.get(opts, :log, :info)
    exclude = Keyword.get(opts, :exclude, ["localhost"])
    {hsts_header(opts), exclude, host, rewrite_on, log}
  end

  @doc """
  Plug pipeline callback.
  """
  def call(conn, {hsts, exclude, host, rewrites, log_level}) do
    conn = rewrite_on(conn, rewrites)

    case conn do
      %{scheme: :https} -> put_hsts_header(conn, hsts, exclude)
      %{} -> redirect_to_https(conn, host, log_level)
    end
  end

  defp rewrite_on(conn, rewrites) do
    Enum.reduce(rewrites, conn, fn
      :x_forwarded_proto, acc ->
        case get_req_header(acc, "x-forwarded-proto") do
          ["https"] -> %{acc | scheme: :https}
          ["http"] -> %{acc | scheme: :http}
          _ -> acc
        end

      other, _acc ->
        raise "unknown rewrite: #{inspect(other)}"
    end)
  end

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

  defp put_hsts_header(%{host: host} = conn, hsts_header, exclude) when is_binary(hsts_header) do
    if :lists.member(host, exclude) do
      conn
    else
      put_resp_header(conn, "strict-transport-security", hsts_header)
    end
  end

  defp put_hsts_header(conn, nil, _), do: conn

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
  # TODO: Deprecate this format
  defp host({:system, env}, host), do: host(System.get_env(env), host)

  defp qs(""), do: ""
  defp qs(qs), do: "?" <> qs
end
