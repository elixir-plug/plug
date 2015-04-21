defmodule Plug.SSL do
  @moduledoc """
  A plug to force SSL

  If the scheme of a request is https, it'll add `strict-transport-security`
  header to enable HTTP Strict Transport Security.

  Otherwise, the request will be redirected to a corresponding location
  with `https` scheme by setting the `location` header of the reponse.
  And the status code will be 301 if method of `conn` is `GET` or `HEAD`,
  or 307 in other situations.

  ## Options

    * `:hsts` - a boolean on enabling HSTS or not and defaults to true.
    * `:expires` - seconds to expires for HSTS, defaults to 31536000(a year).
    * `:subdomains` - a boolean on including subdomains or not in HSTS,
      defaults to false.
    * `:host` - a new host to redirect to if the request's scheme is `http`.
  """
  @behaviour Plug

  import Plug.Conn
  alias Plug.Conn

  def init(opts) do
    hsts       = Keyword.get(opts, :hsts, true)
    expires    = Keyword.get(opts, :expires, 31536000)
    subdomains = Keyword.get(opts, :subdomains, false)
    hsts = if hsts, do: [expires: expires, subdomains: subdomains], else: false

    host = Keyword.get(opts, :host)

    %{hsts_header: hsts_header(hsts),
      host: host}
  end

  def call(conn, config) do
    if conn.scheme == :https do
      register_before_send(conn, &(put_hsts_header(&1, config[:hsts_header])))
    else
      redirect_to_https(conn, config[:host])
    end
  end

  # http://tools.ietf.org/html/draft-hodges-strict-transport-sec-02
  defp hsts_header(false), do: nil
  defp hsts_header(options) do
    value = "max-age=#{options[:expires]}"
    if options[:subdomains], do: "#{value}; includeSubDomains", else: value
  end

  defp put_hsts_header(conn, hsts_header) when is_binary(hsts_header) do
    put_resp_header(conn, "strict-transport-security", hsts_header)
  end
  defp put_hsts_header(conn, _), do: conn

  defp redirect_to_https(%Conn{host: host} = conn, custom_host) do
    status = if conn.method in ~w(HEAD GET), do: 301, else: 307

    uri = %URI{scheme: "https", host: custom_host || host,
               path: full_path(conn), query: conn.query_string}

    conn
    |> put_resp_header("location", to_string(uri))
    |> send_resp(status, "")
    |> halt
  end
end
