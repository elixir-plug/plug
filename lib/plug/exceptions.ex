# This file defines the Plug.Exception protocol and
# the exceptions that implement such protocol.

defprotocol Plug.Exception do
  @moduledoc """
  A protocol that extends exceptions to be status code aware.
  """

  @fallback_to_any true

  @doc """
  Receives an exception and returns its status code.
  """
  @spec status(t) :: Plug.Conn.status
  def status(exception)
end

defimpl Plug.Exception, for: Any do
  def status(_), do: 500
end
