defmodule Plug.Adapters.Elli.Handler do
  @behaviour :elli_handler
  @moduledoc false

  @connection Plug.Adapters.Elli.Connection


  def handle(req, { plug, opts }) do
    case plug.call(@connection.conn(req), opts) do
      { stat, Plug.Conn[adapter: { @connection, req }, resp_body: resp, state: state] } when stat in [:ok, :halt] ->
        if nil?(resp), do: { 204, [], "" }, else: resp
      other ->
        raise "the Elli adapter expected a plug to return { :ok, conn } " <>
              "or { :halt, conn }, instead we got: #{inspect other}"
    end
  end

  def handle_event(_type, _args, _) do
    :ok
  end

end
