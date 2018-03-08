defmodule Plug.SSL do
  @moduledoc """
  A plug to force SSL connections.

  If the scheme of a request is `https`, it'll add a `strict-transport-security`
  header to enable HTTP Strict Transport Security.

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
    * `:expires` - seconds to expires for HSTS, defaults to `31_536_000` (a year).
    * `:preload` - a boolean to request inclusion on the HSTS preload list
       (for full set of required flags, see:
       [Chromium HSTS submission site](https://hstspreload.org)),
      defaults to `false`
    * `:subdomains` - a boolean on including subdomains or not in HSTS,
      defaults to `false`
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
  alias Plug.Conn

  def init(opts) do
    host = Keyword.get(opts, :host)
    rewrite_on = Keyword.get(opts, :rewrite_on, [])
    log = Keyword.get(opts, :log, :info)
    {hsts_header(opts), host, rewrite_on, log}
  end

  def call(conn, {hsts, host, rewrites, log_level}) do
    conn = rewrite_on(conn, rewrites)

    case conn do
      %{scheme: :https} -> put_hsts_header(conn, hsts)
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

  defp put_hsts_header(conn, hsts_header) when is_binary(hsts_header) do
    put_resp_header(conn, "strict-transport-security", hsts_header)
  end

  defp put_hsts_header(conn, _), do: conn

  defp redirect_to_https(%Conn{host: host} = conn, custom_host, log_level) do
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
