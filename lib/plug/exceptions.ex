# This file defines the Plug.Exception protocol and
# the exceptions that implement such protocol.

defprotocol Plug.Exception do
  @moduledoc """
  This protocol extends exceptions so Plug knows how to handle
  and translate them to the proper status code.
  """

  @fallback_to_any true

  @doc """
  Receives an exception and returns the status code it represents.
  """
  def status(exception)
end

defimpl Plug.Exception, for: Any do
  def status(_), do: 500
end
