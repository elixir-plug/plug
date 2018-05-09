defmodule Plug.Adapters.Cowboy2.Handler do
  @moduledoc false
  @connection Plug.Adapters.Cowboy2.Conn
  @already_sent {:plug_conn, :sent}

  def init(req, {plug, opts}) do
    conn = @connection.conn(req)

    try do
      %{adapter: {@connection, req}} =
        conn
        |> plug.call(opts)
        |> maybe_send(plug)

      {:ok, req, {plug, opts}}
    catch
      :error, value ->
        stack = System.stacktrace()
        exception = Exception.normalize(:error, value, stack)
        exit({{exception, stack}, {plug, :call, [conn, opts]}})

      :throw, value ->
        stack = System.stacktrace()
        exit({{{:nocatch, value}, stack}, {plug, :call, [conn, opts]}})

      :exit, value ->
        exit({value, {plug, :call, [conn, opts]}})
    after
      receive do
        @already_sent -> :ok
      after
        0 -> :ok
      end
    end
  end

  defp maybe_send(%Plug.Conn{state: :unset}, _plug), do: raise(Plug.Conn.NotSentError)
  defp maybe_send(%Plug.Conn{state: :set} = conn, _plug), do: Plug.Conn.send_resp(conn)
  defp maybe_send(%Plug.Conn{} = conn, _plug), do: conn

  defp maybe_send(other, plug) do
    raise "Cowboy2 adapter expected #{inspect(plug)} to return Plug.Conn but got: " <>
            inspect(other)
  end
end
