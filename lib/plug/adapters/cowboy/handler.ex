defmodule Plug.Adapters.Cowboy.Handler do
  @behaviour :cowboy_http_handler
  @moduledoc false

  require :cowboy_req
  @connection Plug.Adapters.Cowboy.Connection

  # HTTP

  def init({ transport, :http }, req, main) when transport in [:tcp, :ssl] do
    case main.call(@connection.conn(req, transport), []) do
      Plug.Conn[adapter: { @connection, req }] ->
        { :ok, req, nil }
      other ->
        raise "Expected a Plug.Conn with Cowboy adapter after request, got: #{inspect other}"
    end
  end

  def handle(req, nil) do
    { :ok, req, nil }
  end

  def terminate(_reason, _req, nil) do
    :ok
  end
end
