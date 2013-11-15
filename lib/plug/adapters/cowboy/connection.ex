defmodule Plug.Adapters.Cowboy.Connection do
  @behaviour Plug.Connection.Spec
  @moduledoc false

  def build(req, transport) do
    { path, req } = :cowboy_req.path req
    { host, req } = :cowboy_req.host req
    { port, req } = :cowboy_req.port req
    { meth, req } = :cowboy_req.method req

    Plug.Conn[
      adapter: { __MODULE__, req },
      host: host,
      port: port,
      method: meth,
      scheme: scheme(transport),
      path_info: split_path(path)
    ]
  end

  def send(req, status, headers, body) do
    { :ok, req } = :cowboy_req.reply(status, headers, body, req)
    req
  end

  defp scheme(:tcp), do: :http
  defp scheme(:ssl), do: :https

  defp split_path(path) do
    segments = :binary.split(path, "/", [:global])
    lc segment inlist segments, segment != "", do: segment
  end
end
