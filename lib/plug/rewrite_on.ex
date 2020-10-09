defmodule Plug.RewriteOn do
  @moduledoc """
  A plug to rewrite the request's host/port/protocol from `x-forwarded-*` headers.

  If your Plug application is behind a proxy that handles HTTPS, you may
  need to tell Plug to parse the proper protocol from the `x-forwarded-*`
  header.

      plug Plug.RewriteOn, [:x_forwarded_host, :x_forwarded_port, :x_forwarded_proto]

  The supported values are:

    * `:x_forwarded_host` - to override the host based on on the "x-forwarded-host" header
    * `:x_forwarded_port` - to override the port based on on the "x-forwarded-port" header
    * `:x_forwarded_proto` - to override the protocol based on on the "x-forwarded-proto" header

  Since rewriting the scheme based on `x-forwarded-*` headers can open up
  security vulnerabilities, only use this plug if:

    * your app is behind a proxy
    * your proxy strips the given `x-forwarded-*` headers from all incoming requests
    * your proxy sets the `x-forwarded-*` headers and sends it to Plug
  """
  @behaviour Plug

  import Plug.Conn, only: [get_req_header: 2]

  @impl true
  def init(header), do: List.wrap(header)

  @impl true
  def call(conn, [:x_forwarded_proto | rewrite_on]) do
    conn
    |> put_scheme(get_req_header(conn, "x-forwarded-proto"))
    |> call(rewrite_on)
  end

  def call(conn, [:x_forwarded_port | rewrite_on]) do
    conn
    |> put_port(get_req_header(conn, "x-forwarded-port"))
    |> call(rewrite_on)
  end

  def call(conn, [:x_forwarded_host | rewrite_on]) do
    conn
    |> put_host(get_req_header(conn, "x-forwarded-host"))
    |> call(rewrite_on)
  end

  def call(_conn, [other | _rewrite_on]) do
    raise "unknown rewrite: #{inspect(other)}"
  end

  def call(conn, []) do
    conn
  end

  defp put_scheme(%{scheme: :http, port: 80} = conn, ["https"]),
    do: %{conn | scheme: :https, port: 443}

  defp put_scheme(conn, ["https"]),
    do: %{conn | scheme: :https}

  defp put_scheme(%{scheme: :https, port: 443} = conn, ["http"]),
    do: %{conn | scheme: :http, port: 80}

  defp put_scheme(conn, ["http"]),
    do: %{conn | scheme: :http}

  defp put_scheme(conn, _scheme),
    do: conn

  defp put_host(conn, [proper_host]),
    do: %{conn | host: proper_host}

  defp put_host(conn, _),
    do: conn

  defp put_port(conn, headers) do
    with [header] <- headers,
         {port, ""} <- Integer.parse(header) do
      %{conn | port: port}
    else
      _ -> conn
    end
  end
end
