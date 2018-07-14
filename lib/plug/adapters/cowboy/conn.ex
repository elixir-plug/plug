defmodule Plug.Adapters.Cowboy.Conn do
  @behaviour Plug.Conn.Adapter
  @moduledoc false

  def conn(req, transport) do
    {path, req} = :cowboy_req.path(req)
    {host, req} = :cowboy_req.host(req)
    {port, req} = :cowboy_req.port(req)
    {meth, req} = :cowboy_req.method(req)
    {hdrs, req} = :cowboy_req.headers(req)
    {qs, req} = :cowboy_req.qs(req)
    {peer, req} = :cowboy_req.peer(req)
    {remote_ip, _} = peer

    %Plug.Conn{
      adapter: {__MODULE__, req},
      host: host,
      method: meth,
      owner: self(),
      path_info: split_path(path),
      peer: peer,
      port: port,
      remote_ip: remote_ip,
      query_string: qs,
      req_headers: hdrs,
      request_path: path,
      scheme: scheme(transport)
    }
  end

  def send_resp(req, status, headers, body) do
    status = Integer.to_string(status) <> " " <> Plug.Conn.Status.reason_phrase(status)
    {:ok, req} = :cowboy_req.reply(status, headers, body, req)
    {:ok, nil, req}
  end

  def send_file(req, status, headers, path, offset, length) do
    %File.Stat{type: :regular, size: size} = File.stat!(path)

    length =
      cond do
        length == :all -> size
        is_integer(length) -> length
      end

    body_fun = fn socket, transport -> transport.sendfile(socket, path, offset, length) end

    {:ok, req} =
      :cowboy_req.reply(status, headers, :cowboy_req.set_resp_body_fun(length, body_fun, req))

    {:ok, nil, req}
  end

  def send_chunked(req, status, headers) do
    {:ok, req} = :cowboy_req.chunked_reply(status, headers, req)
    {:ok, nil, req}
  end

  def chunk(req, body) do
    :cowboy_req.chunk(body, req)
  end

  def read_req_body(req, opts \\ []) do
    :cowboy_req.body(req, opts)
  end

  def inform(_req, _path, _headers) do
    {:error, :not_supported}
  end

  def push(_req, _path, _headers) do
    {:error, :not_supported}
  end

  def get_peer_data(req) do
    {{ip, port}, _} = :cowboy_req.peer(req)

    %{
      address: ip,
      port: port,
      ssl_cert: nil
    }
  end

  def get_http_protocol(req) do
    {version, _} = :cowboy_req.version(req)
    version
  end

  ## Helpers

  defp scheme(:tcp), do: :http
  defp scheme(:ssl), do: :https

  defp split_path(path) do
    segments = :binary.split(path, "/", [:global])
    for segment <- segments, segment != "", do: segment
  end
end
