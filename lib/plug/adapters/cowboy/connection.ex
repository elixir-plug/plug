defmodule Plug.Adapters.Cowboy.Connection do
  @behaviour Plug.Connection.Adapter
  @moduledoc false

  def conn(req, transport) do
    { path, req } = :cowboy_req.path req
    { host, req } = :cowboy_req.host req
    { port, req } = :cowboy_req.port req
    { meth, req } = :cowboy_req.method req
    { hdrs, req } = :cowboy_req.headers req
    { qs, req }   = :cowboy_req.qs req

    Plug.Conn[
      adapter: { __MODULE__, req },
      host: host,
      method: meth,
      path_info: split_path(path),
      port: port,
      query_string: qs,
      req_headers: hdrs,
      scheme: scheme(transport)
    ]
  end

  def send_resp(req, status, headers, body) do
    { :ok, req } = :cowboy_req.reply(status, headers, body, req)
    req
  end

  def stream_req_body(req, limit) do
    :cowboy_req.stream_body(limit, req)
  end

  def parse_req_multipart(req, limit, params, callback) do
    { :ok, limit, acc, req } = parse_multipart(req, limit, [], callback)

    if limit > 0 do
      params = Enum.reduce(acc, params, &Plug.Connection.Query.decode_pair(&1, &2))
      { :ok, params, req }
    else
      { :too_large, req }
    end
  end

  ## Helpers

  defp scheme(:tcp), do: :http
  defp scheme(:ssl), do: :https

  defp split_path(path) do
    segments = :binary.split(path, "/", [:global])
    lc segment inlist segments, segment != "", do: segment
  end

  ## Multipart

  defp parse_multipart({ :headers, headers, req }, limit, acc, callback) when limit >= 0 do
    case callback.(headers) do
      { :binary, name } ->
        { :ok, limit, body, req } = parse_multipart_body(:cowboy_req.multipart_data(req), limit, "")
        parse_req_multipart(:cowboy_req.multipart_data(req), limit, [{ name, body }|acc], callback)

      { :file, name, file, Plug.Upload.File[] = uploaded } ->
        { :ok, limit, req } = parse_multipart_file(:cowboy_req.multipart_data(req), limit, file)
        parse_req_multipart(:cowboy_req.multipart_data(req), limit, [{ name, uploaded }|acc], callback)

      :skip ->
        { :ok, req } = :cowboy_req.multipart_skip(req)
        parse_req_multipart(:cowboy_req.multipart_data(req), limit, acc, callback)
    end
  end

  defp parse_multipart({ :headers, _headers, req }, limit, acc, _callback) do
    { :ok, limit, acc, req }
  end

  defp parse_multipart({ :eof, req }, limit, acc, _callback) do
    { :ok, limit, acc, req }
  end

  defp parse_multipart_body({ :body, tail, req }, limit, body) when limit >= 0 do
    parse_multipart_body(R.multipart_data(req), limit - byte_size(tail), body <> tail)
  end

  defp parse_multipart_body({ :body, _tail, req }, limit, body) do
    { :ok, limit, body, req }
  end

  defp parse_multipart_body({ :end_of_part, req }, limit, body) do
    { :ok, limit, body, req }
  end

  defp parse_multipart_file({ :body, tail, req }, limit, file) when limit >= 0 do
    :file.write(file, tail)
    parse_multipart_file(R.multipart_data(req), limit - byte_size(tail), file)
  end

  defp parse_multipart_file({ :body, _tail, req }, limit, file) do
    :file.close(file)
    { :ok, limit, req }
  end

  defp parse_multipart_file({ :end_of_part, req }, limit, file) do
    :file.close(file)
    { :ok, limit, req }
  end
end
