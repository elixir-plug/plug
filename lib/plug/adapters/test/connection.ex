defmodule Plug.Adapters.Test.Connection do
  @behaviour Plug.Connection.Adapter
  @moduledoc false

  defrecord State, [:method, :req_body, :resp_body]

  ## Test helpers

  def conn(method, uri, body_or_params // [], opts // []) do
    uri     = URI.parse(uri)
    method  = method |> to_string |> String.upcase
    headers = opts[:headers] || []

    { body, _params } = body_or_params(body_or_params)
    state = State[method: method, req_body: body, resp_body: nil]

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

  def sent_body(State[resp_body: body]),
    do: body

  ## Connection adapter

  def send_resp(State[method: "HEAD"] = state, _status, _headers, _body),
    do: state.resp_body("")
  def send_resp(State[] = state, _status, _headers, body),
    do: state.resp_body(body)

  def stream_req_body(State[req_body: body] = state, _limit) when byte_size(body) == 0,
    do: { :done, state }
  def stream_req_body(State[req_body: body] = state, limit) do
    size = min(byte_size(body), limit)
    data = :binary.part(body, 0, size)
    rest = :binary.part(body, size, byte_size(body) - size)
    { :ok, data, state.req_body(rest) }
  end

  ## Private helpers

  defp body_or_params(body) when is_binary(body),
    do: { body, nil }
  defp body_or_params(params) when is_list(params),
    do: { "", params }

  defp split_path(path) do
    segments = :binary.split(path, "/", [:global])
    lc segment inlist segments, segment != "", do: segment
  end
end
