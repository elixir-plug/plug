defmodule Plug.Adapters.Cowboy.Conn do
  @behaviour Plug.Conn.Adapter
  @moduledoc false

  alias :cowboy_req, as: Request

  def conn(req, transport) do
    {path, req} = Request.path req
    {host, req} = Request.host req
    {port, req} = Request.port req
    {meth, req} = Request.method req
    {hdrs, req} = Request.headers req
    {qs, req}   = Request.qs req

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
    {:ok, req} = Request.reply(status, headers, body, req)
    {:ok, nil, req}
  end

  def send_file(req, status, headers, path) do
    %File.Stat{type: :regular, size: size} = File.stat!(path)
    body_fun = fn(socket, transport) -> transport.sendfile(socket, path) end

    {:ok, req} = Request.reply(status, headers, Request.set_resp_body_fun(size, body_fun, req))
    {:ok, nil, req}
  end

  def send_chunked(req, status, headers) do
    {:ok, req} = Request.chunked_reply(status, headers, req)
    {:ok, nil, req}
  end

  def chunk(req, body) do
    Request.chunk(body, req)
  end

  def read_req_body(req, opts \\ []) do
    Request.body(req, opts)
  end

  def parse_req_multipart(req, limit, callback) do
    {:ok, limit, acc, req} = parse_multipart(Request.part(req), limit, %{}, callback)

    if limit > 0 do
      params = Enum.reduce(acc, %{}, &Plug.Conn.Query.decode_pair/2)
      {:ok, params, req}
    else
      {:error, :too_large, req}
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

  defp parse_multipart({:ok, headers, req}, limit, acc, callback) when limit >= 0 do
    case callback.(headers) do
      {:binary, name} ->
        {:ok, limit, body, req} = parse_multipart_body(Request.part_body(req), limit, "")
        parse_multipart(Request.part(req), limit, Map.put(acc, name, body), callback)

      {:file, name, file, %Plug.Upload{} = uploaded} ->
        {:ok, limit, req} = parse_multipart_file(Request.part_body(req), limit, file)
        parse_multipart(Request.part(req), limit, Map.put(acc, name, uploaded), callback)

      :skip ->
        {:ok, req} = Request.multipart_skip(req)
        parse_multipart(Request.part(req), limit, acc, callback)
    end
  end

  defp parse_multipart({:ok, _headers, req}, limit, acc, _callback) do
    {:ok, limit, acc, req}
  end

  defp parse_multipart({:done, req}, limit, acc, _callback) do
    {:ok, limit, acc, req}
  end

  defp parse_multipart_body({:more, tail, req}, limit, body) when limit >= 0 do
    parse_multipart_body(Request.part_body(req), limit - byte_size(tail), body <> tail)
  end

  defp parse_multipart_body({:more, _tail, req}, limit, body) do
    {:ok, limit, body, req}
  end

  defp parse_multipart_body({:ok, tail, req}, limit, body) when limit >= byte_size(tail) do
    {:ok, limit, body <> tail, req}
  end

  defp parse_multipart_body({:ok, _tail, req}, limit, body) do
    {:ok, limit, body, req}
  end

  defp parse_multipart_file({:more, tail, req}, limit, file) when limit >= 0 do
    :file.write(file, tail)
    parse_multipart_file(Request.part_body(req), limit - byte_size(tail), file)
  end

  defp parse_multipart_file({:more, _tail, req}, limit, file) do
    :file.close(file)
    {:ok, limit, req}
  end

  defp parse_multipart_file({:ok, tail, req}, limit, file) when limit >= byte_size(tail) do
    :file.write(file, tail)
    :file.close(file)
    {:ok, limit, req}
  end

  defp parse_multipart_file({:ok, _tail, req}, limit, file) do
    :file.close(file)
    {:ok, limit, req}
  end
end
