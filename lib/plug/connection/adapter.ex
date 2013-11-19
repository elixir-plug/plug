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
  defcallback send_resp(payload, Conn.status, Conn.headers, Conn.body) :: payload

  @doc """
  Streams the request body.

  An approximate limit of data to be read from the socket per stream
  can be passed as argument.
  """
  defcallback stream_req_body(payload, limit :: pos_integer) ::
              { :ok, data :: binary, payload } | { :done, payload }
end
