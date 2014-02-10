defmodule Plug.Wrapper do
  @moduledoc """
  Definition of a plug wrapper.

  For more information about wrappers, check out the
  docs in the `Plug` module.
  """
  use Behaviour

  defcallback init(Plug.opts) :: Plug.opts
  defcallback wrap(Plug.Conn.t, Plug.opts, (Plug.Conn.t -> Plug.Conn.t)) :: Plug.Conn.t
end