defmodule Plug.Session.Store do
  @moduledoc """
  Specification for session stores.
  """
  use Behaviour

  @type sid :: term | nil
  @type cookie :: binary
  @type session :: map

  @moduledoc """
  Initializes the store.

  The options returned from this function will be given
  to `get/2`, `put/3` and `delete/2`.
  """
  defcallback init(Plug.opts) :: Plug.opts

  @moduledoc """
  Parses the given cookie.

  Returns a session id and the session contents. The session id is any
  value that can be used to identify the session by the store.

  The session id may be nil in case the cookie does not identify any
  value in the store. The session contents must be a map.
  """
  defcallback get(cookie, Plug.opts) :: {sid, session}

  @moduledoc """
  Stores the session associated with given session id.

  If `nil` is given as id, a new session id should be
  generated and returned.
  """
  defcallback put(sid, any, Plug.opts) :: cookie

  @moduledoc """
  Removes the session associated with given session id from the store.
  """
  defcallback delete(sid, Plug.opts) :: :ok
end
