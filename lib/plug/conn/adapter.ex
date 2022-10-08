defmodule Plug.Conn.Adapter do
  @moduledoc """
  Specification of the connection adapter API implemented by webservers.
  """
  alias Plug.Conn

  @type http_protocol :: :"HTTP/1" | :"HTTP/1.1" | :"HTTP/2" | atom
  @type payload :: term
  @type peer_data :: %{
          address: :inet.ip_address(),
          port: :inet.port_number(),
          ssl_cert: binary | nil
        }

  @doc """
  Function used by adapters to create a new connection.
  """
  def conn(adapter, method, uri, remote_ip, req_headers) do
    %URI{path: path, host: host, port: port, query: qs, scheme: scheme} = uri

    %Plug.Conn{
      adapter: adapter,
      host: host,
      method: method,
      owner: self(),
      path_info: split_path(path),
      port: port,
      remote_ip: remote_ip,
      query_string: qs || "",
      req_headers: req_headers,
      request_path: path,
      scheme: String.to_atom(scheme)
    }
  end

  defp split_path(path) do
    segments = :binary.split(path, "/", [:global])
    for segment <- segments, segment != "", do: segment
  end

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
  @callback send_resp(
              payload,
              status :: Conn.status(),
              headers :: Conn.headers(),
              body :: Conn.body()
            ) ::
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
  @callback send_file(
              payload,
              status :: Conn.status(),
              headers :: Conn.headers(),
              file :: binary,
              offset :: integer,
              length :: integer | :all
            ) :: {:ok, sent_body :: binary | nil, payload}

  @doc """
  Sends the given status, headers as the beginning of
  a chunked response to the client.

  Webservers are advised to return `nil` as the sent_body,
  as the body can no longer be manipulated. However, the
  test implementation returns the actual body so it can
  be used during testing.
  """
  @callback send_chunked(payload, status :: Conn.status(), headers :: Conn.headers()) ::
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
  @callback chunk(payload, body :: Conn.body()) ::
              :ok | {:ok, sent_body :: binary, payload} | {:error, term}

  @doc """
  Reads the request body.

  Read the docs in `Plug.Conn.read_body/2` for the supported
  options and expected behaviour.
  """
  @callback read_req_body(payload, options :: Keyword.t()) ::
              {:ok, data :: binary, payload}
              | {:more, data :: binary, payload}
              | {:error, term}

  @doc """
  Push a resource to the client.

  If the adapter does not support server push then `{:error, :not_supported}`
  should be returned.
  """
  @callback push(payload, path :: String.t(), headers :: Keyword.t()) :: :ok | {:error, term}

  @doc """
  Send an informational response to the client.

  If the adapter does not support inform, then `{:error, :not_supported}`
  should be returned.
  """
  @callback inform(payload, status :: Conn.status(), headers :: Keyword.t()) ::
              :ok | {:error, term}

  @doc """
  Attempt to upgrade the connection with the client.

  If the adapter does not support the indicated upgrade, then `{:error, :not_supported}` should be
  be returned.

  If the adapter supports the indicated upgrade but is unable to proceed with it (due to
  a negotiation error, invalid opts being passed to this function, or some other reason), then an
  arbitrary error may be returned. Note that an adapter does not need to process the actual
  upgrade within this function; it is a wholly supported failure mode for an adapter to attempt
  the upgrade process later in the connection lifecycle and fail at that point.
  """
  @callback upgrade(payload, protocol :: atom, opts :: term) :: {:ok, payload} | {:error, term}

  @doc """
  Returns peer information such as the address, port and ssl cert.
  """
  @callback get_peer_data(payload) :: peer_data()

  @doc """
  Returns the HTTP protocol and its version.
  """
  @callback get_http_protocol(payload) :: http_protocol
end
