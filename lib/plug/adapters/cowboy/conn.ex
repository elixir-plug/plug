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
    {peer, req} = Request.peer req
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
    {:ok, req} = Request.reply(status, headers, body, req)
    {:ok, nil, req}
  end

  def send_file(req, status, headers, path, offset, length) do
    %File.Stat{type: :regular, size: size} = File.stat!(path)

    length =
      cond do
        length == :all -> size
        is_integer(length) -> length
      end

    body_fun = fn(socket, transport) -> transport.sendfile(socket, path, offset, length) end

    {:ok, req} = Request.reply(status, headers, Request.set_resp_body_fun(length, body_fun, req))
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

  def parse_req_multipart(req, opts, callback) do
    # We need to remove the length from the list
    # otherwise cowboy will attempt to load the
    # whole length at once.
    {limit, opts} = Keyword.pop(opts, :length, 8_000_000)
    {:ok, limit, acc, req} = parse_multipart(Request.part(req), limit, opts, [], callback)

    params = Enum.reduce(acc, %{}, &Plug.Conn.Query.decode_pair/2)

    if limit > 0 do
      {:ok, params, req}
    else
      {:more, params, req}
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

  defp parse_multipart({:ok, headers, req}, limit, opts, acc, callback) when limit >= 0 do
    case callback.(headers) do
      {:binary, name} ->
        {:ok, limit, body, req} =
          parse_multipart_body(Request.part_body(req, opts), limit, opts, "")

        Plug.Conn.Utils.validate_utf8!(body, Plug.Parsers.BadEncodingError, "multipart body")
        parse_multipart(Request.part(req), limit, opts, [{name, body}|acc], callback)

      {:file, name, path, %Plug.Upload{} = uploaded} ->
        {:ok, file} = File.open(path, [:write, :binary, :delayed_write, :raw])

        {:ok, limit, req} =
          parse_multipart_file(Request.part_body(req, opts), limit, opts, file)

        :ok = File.close(file)
        parse_multipart(Request.part(req), limit, opts, [{name, uploaded}|acc], callback)

      :skip ->
        parse_multipart(Request.part(req), limit, opts, acc, callback)
    end
  end

  defp parse_multipart({:ok, _headers, req}, limit, _opts, acc, _callback) do
    {:ok, limit, acc, req}
  end

  defp parse_multipart({:done, req}, limit, _opts, acc, _callback) do
    {:ok, limit, acc, req}
  end

  defp parse_multipart_body({:more, tail, req}, limit, opts, body) when limit >= byte_size(tail) do
    parse_multipart_body(Request.part_body(req, opts), limit - byte_size(tail), opts, body <> tail)
  end

  defp parse_multipart_body({:more, tail, req}, limit, _opts, body) do
    {:ok, limit - byte_size(tail), body, req}
  end

  defp parse_multipart_body({:ok, tail, req}, limit, _opts, body) when limit >= byte_size(tail) do
    {:ok, limit - byte_size(tail), body <> tail, req}
  end

  defp parse_multipart_body({:ok, tail, req}, limit, _opts, body) do
    {:ok, limit - byte_size(tail), body, req}
  end

  defp parse_multipart_file({:more, tail, req}, limit, opts, file) when limit >= byte_size(tail) do
    IO.binwrite(file, tail)
    parse_multipart_file(Request.part_body(req, opts), limit - byte_size(tail), opts, file)
  end

  defp parse_multipart_file({:more, tail, req}, limit, _opts, _file) do
    {:ok, limit - byte_size(tail), req}
  end

  defp parse_multipart_file({:ok, tail, req}, limit, _opts, file) when limit >= byte_size(tail) do
    IO.binwrite(file, tail)
    {:ok, limit - byte_size(tail), req}
  end

  defp parse_multipart_file({:ok, tail, req}, limit, _opts, _file) do
    {:ok, limit - byte_size(tail), req}
  end
end
