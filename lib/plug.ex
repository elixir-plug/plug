defmodule Plug do
  @moduledoc """
  Specification for a plug.

  A plug is any Elixir function that receives two arguments: a
  `Plug.Conn` record and a set of keywords options. This function
  must return a tuple, where the first element is an atom and
  the second one is the updated `Plug.Conn`.

  While the first element can be any atom, two values have specific
  meaning to plug:

  * `:ok` - pass the connection to the next plug in the stack
  * `:halt` - halts the current and all other stacks

  Any other values means the connection should halt but it can
  be handled by some of other part of the stack that will be
  able to forward the connection to possibly another stack.

  When defined in a module, it is common for the plug function
  to be named `call/2`.
  """

  use Application.Behaviour

  @doc false
  def init(_plug, opts) do
    opts
  end

  @doc false
  def start(_type, _args) do
    Plug.Supervisor.start_link
  end
end
