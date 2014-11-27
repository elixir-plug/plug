defmodule Plug.Adapters.Cowboy.Handler do
  @moduledoc false
  @connection Plug.Adapters.Cowboy.Conn

  def init({transport, :http}, req, {plug, opts}) when transport in [:tcp, :ssl] do
    {:upgrade, :protocol, __MODULE__, req, {transport, plug, opts}}
  end

  def upgrade(req, env, __MODULE__, {transport, plug, opts}) do
    conn = @connection.conn(req, transport)
    try do
      case plug.call(conn, opts) do
        %Plug.Conn{adapter: {@connection, req}} ->
          {:ok, req, [{:result, :ok} | env]}
        other ->
          raise "Cowboy adapter expected #{inspect plug} to return Plug.Conn but got: #{inspect other}"
      end
    catch
      :error, value ->
        stack = System.stacktrace()
        exception = Exception.normalize(:error, value, stack)
        reason = {{exception, stack}, {plug, :call, [conn, opts]}}
        terminate(reason, req, stack)
      :throw, value ->
        stack = System.stacktrace()
        reason = {{{:nocatch, value}, stack}, {plug, :call, [conn, opts]}}
        terminate(reason, req, stack)
      :exit, value ->
        stack = System.stacktrace()
        reason = {value, {plug, :call, [conn, opts]}}
        terminate(reason, req, stack)
    end
  end

  defp terminate(reason, req, stack) do
    :cowboy_req.maybe_reply(stack, req)
    exit(reason)
  end
end
