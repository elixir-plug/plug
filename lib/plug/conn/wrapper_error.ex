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
  Reraises an error or a wrapped one.
  """
  def reraise(%__MODULE__{stack: stack} = reason) do
    :erlang.raise(:error, reason, stack)
  end

  @deprecated "Use reraise/1 or reraise/4 instead"
  def reraise(conn, kind, reason) do
    reraise(conn, kind, reason, System.stacktrace())
  end

  def reraise(_conn, :error, %__MODULE__{stack: stack} = reason, _stack) do
    :erlang.raise(:error, reason, stack)
  end

  def reraise(conn, :error, reason, stack) do
    wrapper = %__MODULE__{conn: conn, kind: :error, reason: reason, stack: stack}
    :erlang.raise(:error, wrapper, stack)
  end

  def reraise(_conn, kind, reason, stack) do
    :erlang.raise(kind, reason, stack)
  end
end
