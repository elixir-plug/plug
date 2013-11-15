defmodule Plug.Connection.Spec do
  use Behaviour

  alias Plug.Conn
  @typep payload :: term

  @doc """
  Sends the given status, headers and body as a response
  back to the client.
  """
  defcallback send(payload, Conn.status, Conn.headers, Conn.body) :: payload
end
