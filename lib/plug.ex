defmodule Plug do
  @moduledoc """
  Specification for a plug.

  A plug is any Elixir function that receives two arguments: a
  `Plug.Conn` record and a set of keywords options.

  There is a second kind of plugs called wrappers. They work the
  same as regular plugs except that they are expected to define
  a function with three arguments, where the third argument is a
  function that receives a `Plug.Conn` record and returns a
  `Plug.Conn`.

  When defined over modules, it is common for those functions to
  be named `plug/2` and `plug/3`.
  """
end
