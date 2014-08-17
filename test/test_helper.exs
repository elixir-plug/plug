ExUnit.start

Logger.configure_backend(:console, colors: [enabled: false], metadata: [:request_id])

defmodule Plug.ProcessStore do
  @behaviour Plug.Session.Store

  def init(_opts) do
    nil
  end

  def get(sid, nil) do
    {sid, Process.get({:session, sid}) || %{}}
  end

  def delete(sid, nil) do
    Process.delete({:session, sid})
    :ok
  end

  def put(nil, data, nil) do
    sid = :crypto.strong_rand_bytes(96) |> Base.encode64
    put(sid, data, nil)
  end

  def put(sid, data, nil) do
    Process.put({:session, sid}, data)
    sid
  end
end
