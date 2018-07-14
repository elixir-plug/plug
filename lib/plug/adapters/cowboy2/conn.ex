defmodule Plug.Adapters.Cowboy2.Conn do
  @behaviour Plug.Conn.Adapter
  @moduledoc false

  def conn(req) do
    %{
      path: path,
      host: host,
      port: port,
      method: method,
      headers: headers,
      qs: qs,
      peer: {remote_ip, _} = peer
    } = req

    %Plug.Conn{
      adapter: {__MODULE__, req},
      host: host,
      method: method,
      owner: self(),
      path_info: split_path(path),
      peer: peer,
      port: port,
      remote_ip: remote_ip,
      query_string: qs,
      req_headers: to_headers_list(headers),
      request_path: path,
      scheme: String.to_atom(:cowboy_req.scheme(req))
    }
  end

  def send_resp(req, status, headers, body) do
    headers = to_headers_map(headers)
    status = Integer.to_string(status) <> " " <> Plug.Conn.Status.reason_phrase(status)
    req = :cowboy_req.reply(status, headers, body, req)
    {:ok, nil, req}
  end

  def send_file(req, status, headers, path, offset, length) do
    %File.Stat{type: :regular, size: size} = File.stat!(path)

    length =
      cond do
        length == :all -> size
        is_integer(length) -> length
      end

    body = {:sendfile, offset, length, path}
    headers = to_headers_map(headers)
    req = :cowboy_req.reply(status, headers, body, req)
    {:ok, nil, req}
  end

  def send_chunked(req, status, headers) do
    headers = to_headers_map(headers)
    req = :cowboy_req.stream_reply(status, headers, req)
    {:ok, nil, req}
  end

  def chunk(req, body) do
    :cowboy_req.stream_body(body, :nofin, req)
  end

  def read_req_body(req, opts \\ []) do
    opts = if is_list(opts), do: :maps.from_list(opts), else: opts
    :cowboy_req.read_body(req, opts)
  end

  def inform(req, status, headers) do
    :cowboy_req.inform(status, to_headers_map(headers), req)
  end

  def push(req, path, headers) do
    opts =
      case {req.port, req.sock} do
        {:undefined, {_, port}} -> %{port: port}
        {port, _} when port in [80, 443] -> %{}
        {port, _} -> %{port: port}
      end

    :cowboy_req.push(path, to_headers_map(headers), req, opts)
  end

  def get_peer_data(%{peer: {ip, port}, cert: cert}) do
    %{
      address: ip,
      port: port,
      ssl_cert: if(cert == :undefined, do: nil, else: cert)
    }
  end

  def get_http_protocol(req) do
    :cowboy_req.version(req)
  end

  ## Helpers

  defp to_headers_list(headers) when is_list(headers) do
    headers
  end

  defp to_headers_list(headers) when is_map(headers) do
    :maps.to_list(headers)
  end

  defp to_headers_map(headers) when is_list(headers) do
    # Group set-cookie headers into a list for a single `set-cookie`
    # key since cowboy 2 requires headers as a map.
    Enum.reduce(headers, %{}, fn
      {key = "set-cookie", value}, acc ->
        case acc do
          %{^key => existing} -> %{acc | key => [value | existing]}
          %{} -> Map.put(acc, key, [value])
        end

      {key, value}, acc ->
        case acc do
          %{^key => existing} -> %{acc | key => existing <> ", " <> value}
          %{} -> Map.put(acc, key, value)
        end
    end)
  end

  defp split_path(path) do
    segments = :binary.split(path, "/", [:global])
    for segment <- segments, segment != "", do: segment
  end
end
