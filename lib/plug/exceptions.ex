# This file defines the Plug.Exception protocol and
# the exceptions that implement such protocol.

defprotocol Plug.Exception do
  @moduledoc """
  A protocol that extends exceptions to be status-code aware.

  By default, it looks for an implementation of the protocol,
  otherwise checks if the exception has the `:plug_status` field
  or simply returns 500.
  """

  @fallback_to_any true

  @doc """
  Receives an exception and returns its HTTP status code.
  """
  @spec status(t) :: Plug.Conn.status()
  def status(exception)

  @spec actions(t) :: Map.t()
  def actions(exception)
end

defimpl Plug.Exception, for: Any do
  def status(%{plug_status: status}) when is_integer(status), do: status
  def status(_), do: 500
  def actions(_), do: %{}
end

defmodule Plug.BadRequestError do
  @moduledoc """
  The request will not be processed due to a client error.
  """

  defexception message: "could not process the request due to client error", plug_status: 400
end

defmodule BadRequestErrorHandler do
  def print_hi do
    IO.puts("HIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII")
  end
end

defimpl Plug.Exception, for: Plug.BadRequestError do
  def status(_), do: :bad_request

  def actions(_exception) do
    %{
      print_hi_to_terminal: %{
        label: "PRINT HIZINHO",
        action: {BadRequestErrorHandler, :print_hi, []}
      }
    }
  end
end

defimpl Plug.Exception, for: Plug.TimeoutError do
  def status(_), do: :gateway_timeout
end

defmodule Plug.TimeoutError do
  @moduledoc """
  Timeout while waiting for the request.
  """

  defexception message: "timeout while waiting for request data", plug_status: 408
end
