defmodule Plug.Connection.Adapter do
  use Behaviour

  alias Plug.Conn
  @typep payload :: term

  @doc """
  Sends the given status, headers and body as a response
  back to the client.

  If the request has method `"HEAD"`, the adapter should
  not return
  """
  defcallback send(payload, Conn.status, Conn.headers, Conn.body) :: payload
end
