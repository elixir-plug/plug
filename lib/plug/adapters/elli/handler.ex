defmodule Plug.Adapters.Elli.Handler do
  @behaviour :elli_handler
  @moduledoc false

  @connection Plug.Adapters.Elli.Connection


  def handle(req, { plug, opts }) do
    pid = spawn_link(__MODULE__, :plug_handler, [req, plug, opts])
    # Put the pid in the process dictionary so that when the request is completed,
    # a response can be send back to the plug handler from handle_event/3.
    Process.put(:plug_pid, pid)
    receive do
      { :plug_response, resp } ->
        if elem(resp, 0) == :chunk do
          # If a chunked response is requested from the plug handler,
          # respond immediately, because Elli doesn't emit a
          # :request_complete event with chunked transfers.
          send(pid, { :elli_handler, :ok })
        end           
        resp
    end
  end

  @response_events [:request_complete, :client_closed, :file_error,
                    :request_throw, :request_error, :request_exit]

  def handle_event(type, _args, _) when type in @response_events do
    send(Process.get(:plug_pid), { :elli_handler, to_result(type) })
    :ok
  end
  def handle_event(_type, _args, _) do
    :ok
  end

  @doc false
  def plug_handler(req, plug, opts) do
    case plug.call(@connection.conn(req), opts) do
      { stat, Plug.Conn[adapter: { @connection, _req }, state: state] = conn } when stat in [:ok, :halt] ->
        cond do
          state in [:set, :unset] ->
            Plug.Connection.send_resp(conn, 204, "")
          state == :chunked ->
            Plug.Connection.chunk(conn, "")
          true -> nil
        end
      other ->
        raise "the Elli adapter expected a plug to return { :ok, conn } " <>
              "or { :halt, conn }, instead we got: #{inspect other}"
    end
  end

  defp to_result(:request_complete), do: :ok
  defp to_result(error), do: { :error, error }

end
