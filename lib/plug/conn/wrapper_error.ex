defmodule Plug.Conn.WrapperError do
  @moduledoc """
  Wraps the connection in an error which is meant
  to be handled upper in the stack.

  Used by both `Plug.Debugger` and `Plug.ErrorHandler`.
  """
  defexception [:conn, :kind, :reason, :stack]

  def message(%{kind: kind, reason: reason, stack: stack}) do
    Exception.format_banner(kind, reason, stack)
  end
end
