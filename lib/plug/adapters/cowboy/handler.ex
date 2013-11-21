defmodule Plug.Adapters.Cowboy.Handler do
  @behaviour :cowboy_http_handler
  @moduledoc false

  require :cowboy_req
  @connection Plug.Adapters.Cowboy.Connection

  def init({ transport, :http }, req, { plug, opts }) when transport in [:tcp, :ssl] do
    case plug.call(@connection.conn(req, transport), opts) do
      { stat, Plug.Conn[adapter: { @connection, req }] } when stat in [:ok, :halt] ->
        { :ok, req, nil }
      other ->
        raise "the Cowboy adapter expected a plug to return { :ok, conn } " <>
              "or { :halt, conn }, instead we got: #{inspect other}"
    end
  end

  def handle(req, nil) do
    { :ok, req, nil }
  end

  def terminate(_reason, _req, nil) do
    :ok
  end
end
