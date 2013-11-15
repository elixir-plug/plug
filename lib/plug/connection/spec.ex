defmodule Plug.Connection.Spec do
  use Behaviour

  defcallback build(term, term) :: term
end
