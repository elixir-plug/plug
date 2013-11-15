defmodule Plug.Adapters.Cowboy.Connection do
  @behaviour Plug.Connection.Spec
  @moduledoc false

  def build(req, _transport) do
    { path, req } = :cowboy_req.path req

    Plug.Conn[
      adapter: { __MODULE__, req },
      path_info: split_path(path)      
    ]
  end

  defp split_path(path) do
    segments = :binary.split(path, "/", [:global])
    lc segment inlist segments, segment != "", do: segment
  end
end
