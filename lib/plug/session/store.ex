defmodule Plug.Session.Store do
  @moduledoc """
  Specification for session stores.
  """
  use Behaviour

  @type sid :: binary

  @moduledoc """
  Initializes the store. The options returned from this function will be given
  to `get/2`, `put/2` and `destroy/2`.
  """
  defcallback init(Plug.opts) :: Plug.opts

  @moduledoc """
  Returns the session associated with given session id.
  """
  defcallback get(sid, Plug.opts) :: any

  @moduledoc """
  Stores the session associated with given session id. If `nil` is given as id
  a new session id should be generated and returned.
  """
  defcallback put(sid | nil, any, Plug.opts) :: sid

  @moduledoc """
  Removes the session associated with given session id from the store.
  """
  defcallback destroy(sid, Plug.opts) :: :ok
end
