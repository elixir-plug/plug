defmodule Plug.Session.Store do
  @moduledoc """
  Specification for session stores.
  """

  @typedoc """
  The internal reference to the session in the store.
  """
  @type sid :: term | nil

  @typedoc """
  The cookie value that will be sent in cookie headers. This value should be
  base64 encoded to avoid security issues.
  """
  @type cookie :: binary

  @typedoc """
  The session contents, the final data to be stored after it has been built
  with `Plug.Conn.put_session/3` and the other session manipulating functions.
  """
  @type session :: map

  @doc """
  Initializes the store.

  The options returned from this function will be given
  to `get/3`, `put/4` and `delete/3`.
  """
  @callback init(Plug.opts()) :: Plug.opts()

  @doc """
  Parses the given cookie.

  Returns a session id and the session contents. The session id is any
  value that can be used to identify the session by the store.

  The session id may be nil in case the cookie does not identify any
  value in the store. The session contents must be a map.
  """
  @callback get(Plug.Conn.t(), cookie, Plug.opts()) :: {sid, session}

  @doc """
  Stores the session associated with given session id.

  If `nil` is given as id, a new session id should be
  generated and returned.
  """
  @callback put(Plug.Conn.t(), sid, any, Plug.opts()) :: cookie

  @doc """
  Removes the session associated with given session id from the store.
  """
  @callback delete(Plug.Conn.t(), sid, Plug.opts()) :: :ok
end
