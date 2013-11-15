defmodule Plug.Adapters.Test.Connection do
  @behaviour Plug.Connection.Adapter
  @moduledoc false

  def conn(method, path) do
    method = method |> to_string |> String.upcase
    Plug.Conn[
      adapter: { __MODULE__, { method, nil } },
      host: "www.example.com",
      port: 80,
      method: method,
      scheme: :http,
      path_info: split_path(path)
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
