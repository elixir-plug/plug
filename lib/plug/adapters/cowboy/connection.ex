defmodule Plug.Adapters.Cowboy.Connection do
  @behaviour Plug.Connection.Adapter
  @moduledoc false

  def conn(req, transport) do
    { path, req } = :cowboy_req.path req
    { host, req } = :cowboy_req.host req
    { port, req } = :cowboy_req.port req
    { meth, req } = :cowboy_req.method req
    { qs, req }   = :cowboy_req.qs req

    Plug.Conn[
      adapter: { __MODULE__, req },
      host: host,
      method: meth,
      path_info: split_path(path),
      port: port,
      query_string: qs,
      scheme: scheme(transport)
    ]
  end

  def send(req, status, headers, body) do
    { :ok, req } = :cowboy_req.reply(status, headers, body, req)
    req
  end

  def stream_body(req) do
    :cowboy_req.stream_body(req)
  end

  defp scheme(:tcp), do: :http
  defp scheme(:ssl), do: :https

  defp split_path(path) do
    segments = :binary.split(path, "/", [:global])
    lc segment inlist segments, segment != "", do: segment
  end
end
