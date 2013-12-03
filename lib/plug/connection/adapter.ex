defmodule Plug.Connection.Adapter do
  @moduledoc """
  Specification of the connection adapter API implemented by webservers
  """
  use Behaviour

  alias Plug.Conn
  @typep payload :: term

  @doc """
  Sends the given status, headers and body as a response
  back to the client.

  If the request has method `"HEAD"`, the adapter should
  not send the response to the client.

  Webservers are advised to return `nil` as the sent_body,
  as the body can no longer be manipulated. However, the
  test implementation returns the actual body so it can
  be used during testing.
  """
  defcallback send_resp(payload, Conn.status, Conn.headers, Conn.body) ::
              { :ok, sent_body :: binary | nil, payload }

  @doc """
  Sends the given status, headers and file as a response
  back to the client.

  If the request has method `"HEAD"`, the adapter should
  not send the response to the client.

  Webservers are advised to return `nil` as the sent_body,
  as the body can no longer be manipulated. However, the
  test implementation returns the actual body so it can
  be used during testing.
  """
  defcallback send_file(payload, Conn.status, Conn.headers, file :: binary) ::
              { :ok, sent_body :: binary | nil, payload }

  @doc """
  Streams the request body.

  An approximate limit of data to be read from the socket per stream
  can be passed as argument.
  """
  defcallback stream_req_body(payload, limit :: pos_integer) ::
              { :ok, data :: binary, payload } | { :done, payload }

  @doc """
  Parses a multipart request.

  This function receives the payload, the body limit and a callback.
  When parsing each multipart segment, the parser should invoke the
  given fallback passing the headers for that segment, before consuming
  the body. The callback will return one of the following values:

  * `{ :binary, name }` - the current segment must be treated as a regular
                          binary value with the given `name`
  * `{ :file, name, file, upload } - the current segment is a file upload with `name`
                                     and contents should be writen to the given `file`
  * `:skip` - this multipart segment should be skipped

  This function can respond with one of the three following values:

  * `{ :ok, params, payload }` - the parameters are already processed as defined per `Conn.params`
  * `{ :too_large, payload } - the request body goes over the given limit
  """
  defcallback parse_req_multipart(payload, limit :: pos_integer, fun) ::
              { :ok, Conn.params, payload } | { :too_large, payload }
end
