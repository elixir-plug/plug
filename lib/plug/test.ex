defmodule Plug.Test do
  @moduledoc """
  Conveniences for testing plugs.

  This module can be used in your test cases, like this:

      use ExUnit.Case, async: true
      use Plug.Test

  Using this module will:

    * import all the functions from this module
    * import all the functions from the `Plug.Conn` module

  By default, Plug tests checks for invalid header keys, e.g. header keys which
  include uppercase letters, and raises a `Plug.Conn.InvalidHeaderError` when it finds one.
  To disable it, set :validate_header_keys_during_test to false on the app config.

      config :plug, :validate_header_keys_during_test, true

  """

  @doc false
  defmacro __using__(_) do
    quote do
      import Plug.Test
      import Plug.Conn
    end
  end

  alias Plug.Conn
  @typep params :: binary | list | map | nil

  @doc """
  Creates a test connection.

  The request `method` and `path` are required arguments. `method` may be any
  value that implements `to_string/1` and it will properly converted and
  normalized (e.g., `:get` or `"post"`).

  The `params_or_body` field must be one of:

  * `nil` - meaning there is no body;
  * a binary - containing a request body. For such cases, `:headers`
    must be given as option with a content-type;
  * a map or list - containing the parameters which will automatically
    set the content-type to multipart. The map or list may contain
    other lists or maps and all entries will be normalized to string
    keys;

  ## Examples

      conn(:get, "/foo?bar=10")
      conn(:get, "/foo", %{bar: 10})
      conn(:post, "/")
      conn("patch", "/", "") |> put_req_header("content-type", "application/json")

  """
  @spec conn(String.Chars.t(), binary, params) :: Conn.t()
  def conn(method, path, params_or_body \\ nil) do
    Plug.Adapters.Test.Conn.conn(%Plug.Conn{}, method, path, params_or_body)
  end

  @doc """
  Returns the sent response.

  This function is useful when the code being invoked crashes and
  there is a need to verify a particular response was sent even with
  the crash. It returns a tuple with `{status, headers, body}`.
  """
  def sent_resp(%Conn{adapter: {Plug.Adapters.Test.Conn, %{ref: ref}}}) do
    case receive_resp(ref) do
      :no_resp ->
        raise "no sent response available for the given connection. " <>
                "Maybe the application did not send anything?"

      response ->
        case receive_resp(ref) do
          :no_resp ->
            send(self(), {ref, response})
            response

          _otherwise ->
            raise "a response for the given connection has been sent more than once"
        end
    end
  end

  defp receive_resp(ref) do
    receive do
      {^ref, response} -> response
    after
      0 -> :no_resp
    end
  end

  @doc """
  Return the informational requests that have been sent.

  This function depends on gathering the messages sent by the test adapter
  when informational messages, such as an early hint, are sent. Calling this function
  will clear the informational request messages from the inbox for the process.
  To assert on multiple informs, the result of the function should be stored in a variable.

  ## Examples

      conn = conn(:get, "/foo", "bar=10")
      informs = Plug.Test.sent_informs(conn)
      assert {"/static/application.css", [{"accept", "text/css"}]} in informs
      assert {"/static/application.js", [{"accept", "application/javascript"}]} in informs
  """
  def sent_informs(%Conn{adapter: {Plug.Adapters.Test.Conn, %{ref: ref}}}) do
    Enum.reverse(receive_informs(ref, []))
  end

  defp receive_informs(ref, informs) do
    receive do
      {^ref, :inform, response} ->
        receive_informs(ref, [response | informs])
    after
      0 -> informs
    end
  end

  @doc """
  Return the assets that have been pushed.

  This function depends on gathering the messages sent by the test adapter
  when assets are pushed. Calling this function will clear the pushed message
  from the inbox for the process. To assert on multiple pushes, the result
  of the function should be stored in a variable.

  ## Examples

      conn = conn(:get, "/foo?bar=10")
      pushes = Plug.Test.sent_pushes(conn)
      assert {"/static/application.css", [{"accept", "text/css"}]} in pushes
      assert {"/static/application.js", [{"accept", "application/javascript"}]} in pushes
  """
  def sent_pushes(%Conn{adapter: {Plug.Adapters.Test.Conn, %{ref: ref}}}) do
    Enum.reverse(receive_pushes(ref, []))
  end

  defp receive_pushes(ref, pushes) do
    receive do
      {^ref, :push, response} ->
        receive_pushes(ref, [response | pushes])
    after
      0 -> pushes
    end
  end

  @doc """
  Puts the http protocol.
  """
  def put_http_protocol(conn, http_protocol) do
    update_in(conn.adapter, fn {adapter, payload} ->
      {adapter, Map.put(payload, :http_protocol, http_protocol)}
    end)
  end

  @doc """
  Puts the peer data.
  """
  def put_peer_data(conn, peer_data) do
    update_in(conn.adapter, fn {adapter, payload} ->
      {adapter, Map.put(payload, :peer_data, peer_data)}
    end)
  end

  @doc """
  Puts a request cookie.
  """
  @spec put_req_cookie(Conn.t(), binary, binary) :: Conn.t()
  def put_req_cookie(conn, key, value) when is_binary(key) and is_binary(value) do
    conn = delete_req_cookie(conn, key)
    %{conn | req_headers: [{"cookie", "#{key}=#{value}"} | conn.req_headers]}
  end

  @doc """
  Deletes a request cookie.
  """
  @spec delete_req_cookie(Conn.t(), binary) :: Conn.t()
  def delete_req_cookie(%Conn{req_cookies: %Plug.Conn.Unfetched{}} = conn, key)
      when is_binary(key) do
    key = "#{key}="
    size = byte_size(key)
    fun = &match?({"cookie", value} when binary_part(value, 0, size) == key, &1)
    %{conn | req_headers: Enum.reject(conn.req_headers, fun)}
  end

  def delete_req_cookie(_conn, key) when is_binary(key) do
    raise ArgumentError, message: "cannot put/delete request cookies after cookies were fetched"
  end

  @doc """
  Moves cookies from a connection into a new connection for subsequent requests.

  This function copies the cookie information in `old_conn` into `new_conn`,
  emulating multiple requests done by clients where cookies are always passed
  forward, and returns the new version of `new_conn`.
  """
  @spec recycle_cookies(Conn.t(), Conn.t()) :: Conn.t()
  def recycle_cookies(new_conn, old_conn) do
    Enum.reduce(Plug.Conn.fetch_cookies(old_conn).cookies, new_conn, fn {key, value}, acc ->
      put_req_cookie(acc, to_string(key), value)
    end)
  end

  @doc """
  Initializes the session with the given contents.

  If the session has already been initialized, the new contents will be merged
  with the previous ones.
  """
  @spec init_test_session(Conn.t(), %{(String.t() | atom) => any}) :: Conn.t()
  def init_test_session(conn, session) do
    conn =
      if conn.private[:plug_session_fetch] do
        Conn.fetch_session(conn)
      else
        conn
        |> Conn.put_private(:plug_session, %{})
        |> Conn.put_private(:plug_session_fetch, :done)
      end

    Enum.reduce(session, conn, fn {key, value}, conn ->
      Conn.put_session(conn, key, value)
    end)
  end
end
