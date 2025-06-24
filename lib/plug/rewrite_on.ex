defmodule Plug.RewriteOn do
  @moduledoc """
  A plug to rewrite the request's host/port/protocol from `x-forwarded-*` headers.

  If your Plug application is behind a proxy that handles HTTPS, you may
  need to tell Plug to parse the proper protocol from the `x-forwarded-*`
  header.

      plug Plug.RewriteOn, [:x_forwarded_host, :x_forwarded_port, :x_forwarded_proto]

  The supported values are:

    * `:x_forwarded_for` - to override the remote IP based on the "x-forwarded-for" header
    * `:x_forwarded_host` - to override the host based on the "x-forwarded-host" header
    * `:x_forwarded_port` - to override the port based on the "x-forwarded-port" header
    * `:x_forwarded_proto` - to override the protocol based on the "x-forwarded-proto" header

  Some HTTPS proxies use nonstandard headers, which can be specified in the list via tuples:

    * `{:remote_ip, header}` - to override the remote IP based on a custom header
    * `{:host, header}` - to override the host based on a custom header
    * `{:port, header}` - to override the port based on a custom header
    * `{:scheme, header}` - to override the protocol based on a custom header

  A tuple representing a Module-Function-Args can also be given as argument
  instead of a list.

  Since rewriting the scheme based on `x-forwarded-*` headers can open up
  security vulnerabilities, only use this plug if:

    * your app is behind a proxy
    * your proxy strips the given `x-forwarded-*` headers from all incoming requests
    * your proxy sets the `x-forwarded-*` headers and sends it to Plug
  """
  @behaviour Plug

  import Plug.Conn, only: [get_req_header: 2]

  @impl true
  def init({_m, _f, _a} = header), do: header
  def init(header), do: List.wrap(header)

  @impl true
  def call(conn, [:x_forwarded_for | rewrite_on]) do
    call(conn, [{:remote_ip, "x-forwarded-for"} | rewrite_on])
  end

  def call(conn, [:x_forwarded_proto | rewrite_on]) do
    call(conn, [{:scheme, "x-forwarded-proto"} | rewrite_on])
  end

  def call(conn, [:x_forwarded_port | rewrite_on]) do
    call(conn, [{:port, "x-forwarded-port"} | rewrite_on])
  end

  def call(conn, [:x_forwarded_host | rewrite_on]) do
    call(conn, [{:host, "x-forwarded-host"} | rewrite_on])
  end

  def call(conn, [{:remote_ip, header} | rewrite_on]) do
    conn
    |> put_remote_ip(get_req_header(conn, header))
    |> call(rewrite_on)
  end

  def call(conn, [{:scheme, header} | rewrite_on]) do
    conn
    |> put_scheme(get_req_header(conn, header))
    |> call(rewrite_on)
  end

  def call(conn, [{:port, header} | rewrite_on]) do
    conn
    |> put_port(get_req_header(conn, header))
    |> call(rewrite_on)
  end

  def call(conn, [{:host, header} | rewrite_on]) do
    conn
    |> put_host(get_req_header(conn, header))
    |> call(rewrite_on)
  end

  def call(_conn, [other | _rewrite_on]) do
    raise "unknown rewrite: #{inspect(other)}"
  end

  def call(conn, []) do
    conn
  end

  def call(conn, {mod, fun, args}) do
    call(conn, apply(mod, fun, args))
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

  defp put_remote_ip(conn, headers) do
    with [header] <- headers,
         [client | _] <- :binary.split(header, ","),
         {:ok, remote_ip} <- :inet.parse_address(String.to_charlist(client)) do
      %{conn | remote_ip: remote_ip}
    else
      _ -> conn
    end
  end
end
