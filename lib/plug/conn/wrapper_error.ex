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

  @doc """
  Wraps an error into the wrapper.
  """
  def wrap(_conn, :error, %__MODULE__{} = reason),
    do: reason
  def wrap(conn, kind, reason),
    do: %__MODULE__{conn: conn, kind: kind, reason: reason, stack: System.stacktrace}
end
