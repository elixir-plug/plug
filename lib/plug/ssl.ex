defmodule Plug.SSL do
  @behaviour Plug

  import Plug.Conn
  alias Plug.Conn

  def init(opts) do
    hsts       = Keyword.get(opts, :hsts, true)
    expires    = Keyword.get(opts, :expires, 31536000)
    subdomains = Keyword.get(opts, :subdomains, false)
    hsts = if hsts, do: [expires: expires, subdomains: subdomains], else: false

    exclude = Keyword.get(opts, :exclude)
    host = Keyword.get(opts, :host)

    %{hsts: hsts,
      exclude: exclude,
      host: host}
  end

  def call(conn, config) do
    cond do
      config[:exclude] && config[:exclude].(conn) -> conn
      conn.scheme == :https ->
        register_before_send(conn, &add_hsts_headers(&1, config[:hsts]))
      true -> redirect_to_https(conn, config[:host])
    end
  end

  # http://tools.ietf.org/html/draft-hodges-strict-transport-sec-02
  defp add_hsts_headers(conn, false), do: conn
  defp add_hsts_headers(conn, hsts) do
    value = "max-age=#{hsts[:expires]}"
    if hsts[:subdomains], do: value = "#{value}; includeSubDomains"
    put_resp_header(conn, "strict-transport-security", value)
  end

  defp redirect_to_https(%Conn{host: host} = conn, custom_host) do
    status = if conn.method in ~w(HEAD GET), do: 301, else: 307

    uri = %URI{scheme: "https", host: custom_host || host,
               path: full_path(conn), query: conn.query_string}
    headers = [{"content-type", "text/html"}, {"location", to_string(uri)}]

    %{conn | resp_headers: headers}
      |> send_resp(status, "")
      |> halt
  end
end
