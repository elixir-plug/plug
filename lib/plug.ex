defmodule Plug do
  @moduledoc """
  Specification for a plug.

  A plug is any Elixir module that defines the function `plug/2`.
  This function receives a `Plug.Conn` as argument and must return
  a `Plug.Conn`. The second argument is a set of options that must
  be used by plugs.

  There is a second kind of plugs called wrappers. They work the
  same as regular plugs except that they are expected to define
  a `plug/3` function, where the third argument is a function that
  receives a `Plug.Conn` and returns a `Plug.Conn`. The specification
  for the wrapper plug can be found in `Plug.Wrapper`.
  """

  use Behaviour

  defcallback plug(Plug.Conn.t, Keyword.t) :: Plug.Conn.t

  defmodule Wrapper do
    @moduledoc """
    A wrapper plug. See `Plug` for more info.
    """

    use Behaviour

    defcallback plug(Plug.Conn.t, Keyword.t, (Plug.Conn.t -> Plug.Conn.t)) :: Plug.Conn.t
  end
end
