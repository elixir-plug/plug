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

  @doc """
  Reads the request body in data chunks.
  The limit of the data to be read can be given as an argument.
  """
  defcallback read(payload, limit :: pos_integer) ::
              { :ok, data :: binary, payload } | { :done, payload }
end
