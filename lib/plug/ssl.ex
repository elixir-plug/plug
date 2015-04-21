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
    {hsts_header(opts), Keyword.get(opts, :host)}
  end

  def call(conn, {hsts, host}) do
    if conn.scheme == :https do
      put_hsts_header(conn, hsts)
    else
      redirect_to_https(conn, host)
    end
  end

  # http://tools.ietf.org/html/draft-hodges-strict-transport-sec-02
  defp hsts_header(opts) do
    if Keyword.get(opts, :hsts, true) do
      expires    = Keyword.get(opts, :expires, 31536000)
      subdomains = Keyword.get(opts, :subdomains, false)

      "max-age=#{expires}" <>
        if(subdomains, do: "; includeSubDomains", else: "")
    end
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
