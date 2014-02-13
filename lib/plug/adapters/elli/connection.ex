defmodule Plug.Adapters.Elli.Connection do
  @behaviour Plug.Connection.Adapter
  @moduledoc false

  require :elli_request, as: R

  defrecordp :elli_req, Record.extract(:req, from: "deps/elli/include/elli.hrl")

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
    send_to_elli({ status, headers, body }, req)
    { :ok, nil, req }
  end

  def send_file(req, status, headers, path) do
    send_to_elli({ status, [{ "content-length", :elli_util.file_size(path) } | headers], { :file, path } }, req)
    { :ok, nil, req }
  end

  def send_chunked(req, _status, headers) do
    send_to_elli({ :chunk, headers }, req)
    { :ok, nil, req }
  end

  def chunk(req, body) do
    R.send_chunk(R.chunk_ref(req), body)
  end

  # Elli actually always fetches the complete body before executing any handler,
  # so this implementation merely exists for compatibility purposes.
  # Also note that a request with a body exceeding the maximum body size specified in
  # Elli's startup options will be discarded before executing any handler.
  def stream_req_body(req, limit) do
    body = R.body(req)
    if body == :done do
      { :done, req }
    else
      size = size(body)
      if limit >= size do
        { :ok, body, elli_req(req, body: :done) }
      else
        { :ok, :binary.part(body, 0, limit), elli_req(req, body: :binary.part(body, limit, size - limit)) }
      end
    end
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

  defp send_to_elli(resp, req) do
    # Although the name is confusing, chunk_ref just returns
    # the pid of the Elli process that executes the Elli handler.
    send(R.chunk_ref(req), { :plug_response, resp })
    receive do
      { :elli_handler, result } -> result
    after
      5_000 -> { :error, :timeout }
    end
  end

end
