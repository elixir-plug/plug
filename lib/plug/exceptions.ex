# This file defines the Plug.Exception protocol and
# the exceptions that implement such protocol.

defprotocol Plug.Exception do
  @moduledoc """
  A protocol that extends exceptions to be status-code aware.

  By default, it looks for an implementation of the protocol,
  otherwise checks if the exception has the `:plug_status` field
  or simply returns 500.

  If the exception has a `:plug_status` field the `:message`
  field will be used if it exists.
  """

  @fallback_to_any true

  @doc """
  Receives an exception and returns its HTTP status code.
  """
  @spec status(t) :: Plug.Conn.status
  def status(exception)

  @doc """
  Receives an exception and returns a message safe to display to users.
  """
  @spec message(t) :: nil | String.t
  def message(exception)
end

defimpl Plug.Exception, for: Any do
  def status(%{plug_status: status}) when is_integer(status), do: status
  def status(_), do: 500

  def message(%{plug_status: status, message: message}) when is_integer(status), do: message
  def message(_), do: nil
end
