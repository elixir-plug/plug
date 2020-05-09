Application.ensure_all_started(:telemetry)
ExUnit.start(assert_receive_timeout: 200)
Logger.configure_backend(:console, colors: [enabled: false], metadata: [:request_id])

defmodule Plug.ProcessStore do
  @behaviour Plug.Session.Store

  def init(_opts) do
    nil
  end

  def get(_conn, sid, nil) do
    {sid, Process.get({:session, sid}) || %{}}
  end

  def delete(_conn, sid, nil) do
    Process.delete({:session, sid})
    :ok
  end

  def put(conn, nil, data, nil) do
    sid = Base.encode64(:crypto.strong_rand_bytes(96))
    put(conn, sid, data, nil)
  end

  def put(_conn, sid, data, nil) do
    Process.put({:session, sid}, data)
    sid
  end
end
