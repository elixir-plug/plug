# In this file we check if at least one of the adapters are implemented.
# Since right now we only support cowboy, the check is straight-forward.
unless Code.ensure_loaded?(:cowboy_req) do
  raise "cannot compile Plug because the :cowboy application is not available. " <>
        "Please ensure it is listed as a dependency before the plug one."
end

defmodule Plug.Conn.Adapter do
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
              {:ok, sent_body :: binary | nil, payload}

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
              {:ok, sent_body :: binary | nil, payload}

  @doc """
  Sends the given status, headers as the beginning of
  a chunked response to the client.

  Webservers are advised to return `nil` as the sent_body,
  as the body can no longer be manipulated. However, the
  test implementation returns the actual body so it can
  be used during testing.
  """
  defcallback send_chunked(payload, Conn.status, Conn.headers) ::
              {:ok, sent_body :: binary | nil, payload}

  @doc """
  Sends a chunk in the chunked response.

  If the request has method `"HEAD"`, the adapter should
  not send the response to the client.

  Webservers are advised to return `:ok` and not modify
  any further state for each chunk. However, the test
  implementation returns the actual body and payload so
  it can be used during testing.
  """
  defcallback chunk(payload, Conn.status) ::
              :ok | {:ok, sent_body :: binary, payload} | {:error, term}

  @doc """
  Reads the request body.

  Read the docs in `Plug.Conn.read_body/2` for the supported
  options and expected behaviour.
  """
  defcallback read_req_body(payload, options :: Keyword.t) ::
              {:ok, data :: binary, payload} |
              {:more, data :: binary, payload} |
              {:error, term}

  @doc """
  Parses a multipart request.

  This function receives the payload, the body limit and a callback.
  When parsing each multipart segment, the parser should invoke the
  given fallback passing the headers for that segment, before consuming
  the body. The callback will return one of the following values:

  * `{:binary, name}` - the current segment must be treated as a regular
                          binary value with the given `name`
  * `{:file, name, file, upload} - the current segment is a file upload with `name`
                                     and contents should be written to the given `file`
  * `:skip` - this multipart segment should be skipped

  This function may return a `:ok` or `:more` tuple. The first one is
  returned when there is no more multipart data to be processed.

  For the supported options, please read `Plug.Conn.read_body/2` docs.
  """
  defcallback parse_req_multipart(payload, options :: Keyword.t, fun) ::
              {:ok, Conn.params, payload} | {:more, Conn.params, payload}

  @doc """
  Parses known request headers into well-defined data-structures.

  If a request header is unknown and/or cannot be parsed, it is returned in the
  form of a raw request header (`{binary, binary}`).

  ## Headers

  The follow list summarizes the the types returned for known request headers.

  ```
  {"accept", [{{Type, SubType, Params}, Quality, AcceptExt}]}
  {"accept-charset", [{Charset, Quality}]}
  {"accept-encoding", [{Encoding, Quality}]}
  {"accept-language", [{LanguageTag, Quality}]}
  {"authorization", {AuthType, Credentials}}
  {"content-length", non_neg_integer}
  {"content-type", {Type, SubType, ContentTypeParams}}
  {"cookie", [{binary, binary}]}
  {"expect", [Expect | {Expect, ExpectValue, Params}]}
  {"if-match", '*' | [{weak | strong, OpaqueTag}]}
  {"if-modified-since", :calendar.datetime()}
  {"if-none-match", '*' | [{weak | strong, OpaqueTag}]}
  {"if-unmodified-since", :calendar.datetime()}
  {"range", {Unit, [Range]}}
  {"sec-websocket-protocol", [binary]}
  {"transfer-encoding", [binary]}
  {"upgrade", [binary]}
  {"x-forwarded-for", [binary]}
  ```

  ## Types

  The following list summarizes the different types referenced in the above
  descriptions of parsed request headers.

  ```
  @type Type :: binary
   @type SubType :: Type
   @type Charset :: Type
   @type Encoding :: Type
   @type LanguageTag :: Type

  @type AuthType :: binary
   @type Expect :: binary
   @type OpaqueTag :: binary
   @type Unit :: binary

  @type Params :: [{binary, binary}]
   @type ContentTypeParams :: Params

  @type Quality :: 0..1000

  @type AcceptExt :: [{binary, binary} | binary]

  @type Username :: binary
  @type Password :: binary
  @type Credentials :: {Username, Password}

  @type Range :: {non_neg_integer, non_neg_integer | infinity} | neg_integer
  ```

  ## Fallback

  If request header parsing is not exposed `Plug.Conn.Utils.parse_header/2` can
  be used as a fallback implementation.
  """
  defcallback parse_req_headers(payload) ::
              {:ok, Conn.p_headers, payload}
end
