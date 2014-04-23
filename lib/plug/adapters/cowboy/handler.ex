defmodule Plug.Adapters.Cowboy.Handler do
  @moduledoc false
  @behaviour :cowboy_http_handler
  @connection Plug.Adapters.Cowboy.Conn

  def init({transport, :http}, req, {plug, opts}) when transport in [:tcp, :ssl] do
    case plug.call(@connection.conn(req, transport), opts) do
      %Plug.Conn{adapter: {@connection, req}} ->
        {:ok, req, nil}
      other ->
        raise "Cowboy adapter expected #{inspect plug} to return Plug.Conn but got: #{inspect other}"
    end
  end

  def handle(req, nil) do
    {:ok, req, nil}
  end

  def terminate(_reason, _req, nil) do
    :ok
  end
end
