defmodule Plug.Adapters.Test.Connection do
  @behaviour Plug.Connection.Adapter
  @moduledoc false

  def conn(method, uri) do
    uri = URI.parse(uri)
    method = method |> to_string |> String.upcase
    Plug.Conn[
      adapter: { __MODULE__, { method, nil } },
      host: uri.host || "www.example.com",
      method: method,
      path_info: split_path(uri.path),
      port: uri.port || 80,
      query_string: uri.query || "",
      scheme: (uri.scheme || "http") |> String.downcase |> binary_to_atom
    ]
  end

  def send({ "HEAD", _ }, _status, _headers, _body) do
    { "HEAD", "" }
  end

  def send({ method, _ }, _status, _headers, body) do
    { method, body }
  end

  defp split_path(path) do
    segments = :binary.split(path, "/", [:global])
    lc segment inlist segments, segment != "", do: segment
  end
end
