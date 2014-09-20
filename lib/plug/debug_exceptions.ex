defmodule Plug.DebugExceptions do

  defmacro __using__(_) do
    quote do
      def call(conn, opts) do
        try do
          super(conn, opts)
        catch
          _, err ->
            debug_error(conn, err)
        end
      end

      @before_compile Plug.DebugExceptions
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      require Logger

      defp debug_error(conn, err) do
        log_error(err)

        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(500, debug_template(err))
      end

      defp log_error(err) do
        Logger.error fn ->
          stacktrace     = System.stacktrace
          exception      = Exception.normalize(:error, err)
          exception_type = exception.__struct__

          """
          #{inspect exception_type}: #{Exception.message(exception)}
          #{Exception.format_stacktrace stacktrace}
          """
        end
      end

      defp debug_template(err) do
        stacktrace     = System.stacktrace
        exception      = Exception.normalize(:error, err)
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
