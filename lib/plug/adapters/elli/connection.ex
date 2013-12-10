defmodule Plug.Adapters.Elli.Connection do
  @behaviour Plug.Connection.Adapter
  @moduledoc false

  require :elli_request, as: R

  def conn(req) do
    { host, port } = split_host_header(R.get_header("Host", req))
    headers  = downcase_fields(R.headers(req))
    Plug.Conn[
      adapter: { __MODULE__, req },
      host: host,
      method: to_string(R.method(req)),
      path_info: R.path(req),
      port: port,
      query_string: R.query_str(req),
      req_headers: headers,
      scheme: :http
    ]
  end

  def send_resp(req, status, headers, body) do
    resp = { status, headers, body }
    { :ok, resp, req }
  end

  def send_file(req, status, headers, path) do
    resp = { status, [{ "content-length", :elli_util.file_size(path) } | headers], { :file, path } }
    { :ok, resp, req }
  end

  def send_chunked(req, _status, headers) do
    resp = { :chunk, headers }
    { :ok, resp, req }
  end

  def chunk(req, body) do
    R.send_chunk(R.chunk_ref(req), body)
  end

  def stream_req_body(_req, _limit) do
    raise UndefinedFunctionError, message: "Streaming of body data is not implemented for the Elli adapter."
  end

  def parse_req_multipart(_req, _limit, _callback) do
    raise UndefinedFunctionError, message: "Multipart parsing is not implemented for the Elli adapter."
  end

  ## Helpers

  defp split_host_header(h) do
    case :binary.split(h, ":") do
      [host, port] -> { host, binary_to_integer(port) }
      [host] -> { host, 80 }
    end
  end

  defp downcase_fields(headers) do
    lc { field, value } inlist headers, do: { String.downcase(field), value }
  end

end
