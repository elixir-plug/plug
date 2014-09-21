defmodule Plug.DebugExceptions do
  @moduledoc """
  Provides tools for debugging in development.

  This module can be used in a module that has a plug stack so it catches errors:

      defmodule MyApp do
        use Plug.Builder
        use Plug.DebugExceptions

        plug :boom

        def boom(conn, _) do
          # Error raised here will be caught, logged and displayed in a debug
          # page complete with a stacktrace and other helpful info
          raise ArgumentError
        end
      end

  Keep in mind that the module has to have a Plug stack. That means doing
  `use Plug.Builder` or `use Plug.Router` before `use Plug.DebugExceptions`.

  There is a default error logging and html template for the debug page and both
  can be overridden. To override, just define a `log_error/1` or `debug_template/1`
  in the module using `Plug.DebugExceptions`.
  """

  @doc false
  defmacro __using__(_) do
    quote do
      require Logger

      def call(conn, opts) do
        try do
          super(conn, opts)
        catch
          _, err ->
            debug_error(conn, err)
        end
      end

      defp debug_error(conn, err) do
        stacktrace     = System.stacktrace
        exception      = Exception.normalize(:error, err)
        debug_data     = {stacktrace, exception}

        log_error(debug_data)

        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(500, debug_template(debug_data))
      end

      defp log_error({stacktrace, exception}) do
        Logger.error fn ->
          exception_type = exception.__struct__

          """
          #{inspect exception_type}: #{Exception.message(exception)}
          #{Exception.format_stacktrace stacktrace}
          """
        end
      end

      defp debug_template({stacktrace, exception}) do
        exception_type = exception.__struct__

        # TODO: Improve below template with a prettier debug page
        """
        <html>
          <h2>(#{inspect exception_type}) #{Exception.message(exception)}</h2>
          <h4>Stacktrace</h4>
          <body>
            <pre>#{Exception.format_stacktrace stacktrace}</pre>
          </body>
        </html>
        """
      end
    end
  end
end
