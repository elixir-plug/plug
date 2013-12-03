defmodule Plug.Adapters.Test.Connection do
  @behaviour Plug.Connection.Adapter
  @moduledoc false

  defrecord State, [:method, :params, :req_body, :chunks]

  ## Test helpers

  def conn(method, uri, body_or_params // [], opts // []) do
    uri     = URI.parse(uri)
    method  = method |> to_string |> String.upcase

    { body, params, headers } = body_or_params(body_or_params, opts[:headers] || [])
    state = State[method: method, params: params, req_body: body]

    Plug.Conn[
      adapter: { __MODULE__, state },
      host: uri.host || "www.example.com",
      method: method,
      path_info: split_path(uri.path),
      port: uri.port || 80,
      req_headers: headers,
      query_string: uri.query || "",
      scheme: (uri.scheme || "http") |> String.downcase |> binary_to_atom
    ]
  end

  ## Connection adapter

  def send_resp(State[method: "HEAD"] = state, _status, _headers, _body),
    do: { :ok, "", state }
  def send_resp(State[] = state, _status, _headers, body),
    do: { :ok, body, state }

  def send_file(State[method: "HEAD"] = state, _status, _headers, _path),
    do: { :ok, "", state }
  def send_file(State[] = state, _status, _headers, path),
    do: { :ok, File.read!(path), state }

  def send_chunked(state, _status, _headers),
    do: { :ok, "", state.chunks("") }
  def chunk(State[method: "HEAD"] = state, _body),
    do: { :ok, "", state }
  def chunk(State[chunks: chunks] = state, body) do
    body = chunks <> body
    { :ok, body, state.chunks(body) }
  end

  def stream_req_body(State[req_body: body] = state, _limit) when byte_size(body) == 0,
    do: { :done, state }
  def stream_req_body(State[req_body: body] = state, limit) do
    size = min(byte_size(body), limit)
    data = :binary.part(body, 0, size)
    rest = :binary.part(body, size, byte_size(body) - size)
    { :ok, data, state.req_body(rest) }
  end

  def parse_req_multipart(State[params: multipart] = state, _limit, _callback) do
    { :ok, multipart, state.params(nil) }
  end

  ## Private helpers

  defp body_or_params(body, headers) when is_binary(body) do
    unless headers["content-type"] do
      raise ArgumentError, message: "a content-type header is required when setting the body in a test connection"
    end
    { body, nil, headers }
  end

  defp body_or_params(params, headers) when is_list(params) do
    headers = Dict.put(headers, "content-type", "multipart/mixed; charset: utf-8")
    { "", stringify_params(params), headers }
  end

  defp stringify_params([{ k, v }|t]),
    do: [{ to_string(k), stringify_params(v) }|stringify_params(t)]
  defp stringify_params([h|t]),
    do: [stringify_params(h)|stringify_params(t)]
  defp stringify_params(other),
    do: other

  defp split_path(path) do
    segments = :binary.split(path, "/", [:global])
    lc segment inlist segments, segment != "", do: segment
  end
end
