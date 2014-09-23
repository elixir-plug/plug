defmodule Plug.Debugger do
  @moduledoc """
  Provides tools for debugging in development.

  This module can be used in any Plug module to catch errors:

      defmodule MyApp do
        use Plug.Builder
        use Plug.Debugger, [root: Path.expand("myapp"), sources: ["web/**/*"]]

        plug :boom

        def boom(conn, _) do
          # Error raised here will be caught, logged and displayed in a debug
          # page complete with a stacktrace and other helpful info
          raise ArgumentError
        end
      end

  Keep in mind that the using module has to have a call/1 function which is part
  of the expected behavior of a Plug module.

  There is a default error logging and html template for the debug page and both
  can be overridden. To override, just define a `log_error/1` or `debug_template/1`
  in the module using `Plug.Debugger`.

  When using this module, make sure to specify `:root` and `:sources`. These are
  required so that the default debug_template will know where to look for files.
  """

  @doc false
  defmacro __using__(env) do
    quote do
      require Logger
      import Plug.Debugger
      alias Plug.Debugger.Frame

      def call(conn, opts) do
        try do
          super(conn, opts)
        catch
          kind, err -> debug_error(conn, kind, err)
        end
      end

      defp debug_error(conn, kind, err) do
        stacktrace  = System.stacktrace
        exception   = Exception.normalize(kind, err)
        debug_data  = {kind, exception, stacktrace}
        root        = unquote(env[:root])
        sources     = unquote(env[:sources])
        assigns     = [
          frames: Frame.generate_frames(stacktrace, root, sources),
          title: title(kind, err),
          message: message(kind, err),
          path: get_path(conn),
          method: conn.method
        ]

        log_error(debug_data)

        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(500, debug_template(assigns))
      end

      defp log_error({kind, exception, stacktrace}) do
        Logger.error fn ->
          """
          #{Exception.format_banner kind, exception, stacktrace}
          #{Exception.format_stacktrace stacktrace}
          """
        end
      end

      ## Template

      require EEx

      EEx.function_from_file :defp, :debug_template,
        Path.expand("template.eex", "lib/plug/debugger"), [:assigns]

      defoverridable [debug_template: 1, log_error: 1]
    end
  end

  ## Helpers

  @doc false
  def title(:error, err), do: inspect err.__struct__
  def title(other, _), do: "unhandled #{other}"

  @doc false
  def get_path(%Plug.Conn{path_info: []}), do: "/"
  def get_path(conn), do: "/" <> Path.join(conn.path_info)

  @doc false
  def message(:error, err), do: Exception.message(err)
  def message(_, err),      do: inspect err

  @doc false
  def h(string) do
    for <<code <- to_string(string)>> do
      << case code do
           ?& -> "&amp;"
           ?< -> "&lt;"
           ?> -> "&gt;"
           ?" -> "&quot;"
           _  -> <<code>>
         end :: binary >>
    end
  end
end
