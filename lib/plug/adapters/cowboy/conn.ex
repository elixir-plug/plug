defmodule Plug.Adapters.Cowboy.Conn do
  @behaviour Plug.Conn.Adapter
  @moduledoc false

  require :cowboy_req, as: R

  def conn(req, transport) do
    {path, req} = R.path req
    {host, req} = R.host req
    {port, req} = R.port req
    {meth, req} = R.method req
    {hdrs, req} = R.headers req
    {qs, req}   = R.qs req

    %Plug.Conn{
      adapter: {__MODULE__, req},
      host: host,
      method: meth,
      path_info: split_path(path),
      port: port,
      query_string: qs,
      req_headers: hdrs,
      scheme: scheme(transport)
   }
  end

  def send_resp(req, status, headers, body) do
    {:ok, req} = R.reply(status, headers, body, req)
    {:ok, nil, req}
  end

  def send_file(req, status, headers, path) do
    File.Stat[type: :regular, size: size] = File.stat!(path)
    body_fun = fn(socket, transport) -> transport.sendfile(socket, path) end

    {:ok, req} = R.reply(status, headers, R.set_resp_body_fun(size, body_fun, req))
    {:ok, nil, req}
  end

  def send_chunked(req, status, headers) do
    {:ok, req} = R.chunked_reply(status, headers, req)
    {:ok, nil, req}
  end

  def chunk(req, body) do
    R.chunk(body, req)
  end

  def stream_req_body(req, limit) do
    R.stream_body(limit, req)
  end

  def parse_req_multipart(req, limit, callback) do
    {:ok, limit, acc, req} = parse_multipart(R.multipart_data(req), limit, %{}, callback)

    if limit > 0 do
      params = Enum.reduce(acc, %{}, &Plug.Conn.Query.decode_pair/2)
      {:ok, params, req}
    else
      {:too_large, req}
    end
  end

  ## Helpers

  defp scheme(:tcp), do: :http
  defp scheme(:ssl), do: :https

  defp split_path(path) do
    segments = :binary.split(path, "/", [:global])
    for segment <- segments, segment != "", do: segment
  end

  ## Multipart

  defp parse_multipart({:headers, headers, req}, limit, acc, callback) when limit >= 0 do
    case callback.(headers) do
      {:binary, name} ->
        {:ok, limit, body, req} = parse_multipart_body(R.multipart_data(req), limit, "")
        parse_multipart(R.multipart_data(req), limit, Map.put(acc, name, body), callback)

      {:file, name, file, %Plug.Upload{} = uploaded} ->
        {:ok, limit, req} = parse_multipart_file(R.multipart_data(req), limit, file)
        parse_multipart(R.multipart_data(req), limit, Map.put(acc, name, uploaded), callback)

      :skip ->
        {:ok, req} = R.multipart_skip(req)
        parse_multipart(R.multipart_data(req), limit, acc, callback)
    end
  end

  defp parse_multipart({:headers, _headers, req}, limit, acc, _callback) do
    {:ok, limit, acc, req}
  end

  defp parse_multipart({:eof, req}, limit, acc, _callback) do
    {:ok, limit, acc, req}
  end

  defp parse_multipart_body({:body, tail, req}, limit, body) when limit >= 0 do
    parse_multipart_body(R.multipart_data(req), limit - byte_size(tail), body <> tail)
  end

  defp parse_multipart_body({:body, _tail, req}, limit, body) do
    {:ok, limit, body, req}
  end

  defp parse_multipart_body({:end_of_part, req}, limit, body) do
    {:ok, limit, body, req}
  end

  defp parse_multipart_file({:body, tail, req}, limit, file) when limit >= 0 do
    :file.write(file, tail)
    parse_multipart_file(R.multipart_data(req), limit - byte_size(tail), file)
  end

  defp parse_multipart_file({:body, _tail, req}, limit, file) do
    :file.close(file)
    {:ok, limit, req}
  end

  defp parse_multipart_file({:end_of_part, req}, limit, file) do
    :file.close(file)
    {:ok, limit, req}
  end
end
