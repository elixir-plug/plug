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

  @type action :: %{label: String.t(), handler: {module(), atom(), list()}}

  @doc """
  Receives an exception and returns its HTTP status code.
  """
  @spec status(t) :: Plug.Conn.status()
  def status(exception)

  @doc """
  Receives an exception and returns the possible actions that could be triggered for that error.
  Should return a list of actions in the following structure:

      %{
        label: "Text that will be displayed in the button",
        handler: {Module, :function, [args]}
      }

  Where:

    * `label` a string/binary that names this action
    * `handler` a MFArgs that will be executed when this action is triggered

  It will be rendered in the `Plug.Debugger` generated error page as buttons showing the `label`
  that upon pressing executes the MFArgs defined in the `handler`.

  ## Examples

      defimpl Plug.Exception, for: ActionableExample do
        def actions(_), do: [%{label: "Print HI", handler: {IO, :puts, ["Hi!"]}}]
      end
  """
  @spec actions(t) :: [action()]
  def actions(exception)
end

defimpl Plug.Exception, for: Any do
  def status(%{plug_status: status}), do: Plug.Conn.Status.code(status)
  def status(_), do: 500
  def actions(_exception), do: []
end

defmodule Plug.BadRequestError do
  @moduledoc """
  An exception raised when the request will not be processed due to a client error.
  """
  defexception message: "could not process the request due to client error.",
               plug_status: 400,
               plug_message: "Bad Request"

  def message(exception) do
    "could not process the request due to client error. \n
    (Status Code: #{exception.plug_status} #{exception.plug_message})"
  end
end

defmodule Plug.BadResponseError do
  @moduledoc """
  An exception raised when the request will not be processed due to a server error.
  """
  defexception message: "could not process the request due to server error.",
               plug_status: 500,
               plug_message: "Internal Server Error"

  def message(exception) do
    "could not process the request due to server error: (Status Code: #{exception.plug_status} #{exception.plug_message})"
  end
end

defmodule Plug.TimeoutError do
  @moduledoc """
  An exception raised when the request times out while waiting for the request.
  """

  defexception message: "timeout while waiting for request data", plug_status: 408
end

defmodule Plug.ResourceNotFoundError do
  @moduledoc """
  An exception raised when the requested resource cannot be located.
  """

  defexception message: "The requested resource could not be found", plug_status: 404
end

defmodule Plug.ClientError do
  @moduledoc """
  An exception raised when the requested resource returned a 4XX status code.
  """

  defexception message: "The requested resource could not be found", plug_status: 404
end

defmodule Plug.ServerError do
  @moduledoc """
  An exception raised when
  """

  defexception message: "The requested resource could not be found", plug_status: 404
end
