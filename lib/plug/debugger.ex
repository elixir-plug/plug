# The debugger is based on Better Errors, under MIT LICENSE.
#
# Copyright (c) 2012 Charlie Somerville
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

defmodule Plug.Debugger do
  @moduledoc """
  A module (**not a plug**) for debugging in development.

  This module is commonly used within a `Plug.Builder` or a `Plug.Router`
  and it wraps the `call/2` function.

  Notice `Plug.Debugger` *does not* catch errors, as errors should still
  propagate so that the Elixir process finishes with the proper reason.
  This module does not perform any logging either, as all logging is done
  by the web server handler.

  **Note:** If this module is used with `Plug.ErrorHandler`, only one of
  them will effectively handle errors. For this reason, it is recommended
  that `Plug.Debugger` is used before `Plug.ErrorHandler` and only in
  particular environments, like `:dev`.

  ## Examples

      defmodule MyApp do
        use Plug.Builder

        if Mix.env == :dev do
          use Plug.Debugger, otp_app: :my_app
        end

        plug :boom

        def boom(conn, _) do
          # Error raised here will be caught and displayed in a debug page
          # complete with a stacktrace and other helpful info.
          raise "oops"
        end
      end

  ## Options

    * `:otp_app` - same as in `wrap/3`

  ## Links to the text editor

  If a `PLUG_EDITOR` environment variable is set, `Plug.Debugger` will
  use it to generate links to your text editor. The variable should be
  set with `__FILE__` and `__LINE__` placeholders which will be correctly
  replaced. For example (with the [TextMate](http://macromates.com) editor):

      txmt://open/?url=file://__FILE__&line=__LINE__

  """

  @already_sent {:plug_conn, :sent}
  import Plug.Conn
  require Logger

  @doc false
  defmacro __using__(opts) do
    quote do
      @plug_debugger unquote(opts)
      @before_compile Plug.Debugger
    end
  end

  @doc false
  defmacro __before_compile__(_) do
    quote location: :keep do
      defoverridable [call: 2]

      def call(conn, opts) do
        try do
          super(conn, opts)
        catch
          kind, reason ->
            Plug.Debugger.__catch__(conn, kind, reason, @plug_debugger)
        end
      end
    end
  end

  @doc false
  def __catch__(_conn, :error, %Plug.Conn.WrapperError{} = wrapper, opts) do
    %{conn: conn, kind: kind, reason: reason, stack: stack} = wrapper
    __catch__(conn, kind, reason, stack, opts)
  end

  def __catch__(conn, kind, reason, opts) do
    __catch__(conn, kind, reason, System.stacktrace, opts)
  end

  defp __catch__(conn, kind, reason, stack, opts) do
    reason = Exception.normalize(kind, reason, stack)
    status = status(kind, reason)

    receive do
      @already_sent ->
        send self(), @already_sent
        log status, kind, reason, stack
        :erlang.raise kind, reason, stack
    after
      0 ->
        render conn, status, kind, reason, stack, opts
        log status, kind, reason, stack
        :erlang.raise kind, reason, stack
    end
  end

  defp log(status, kind, reason, stack) when status < 500,
    do: Logger.warn(Exception.format(kind, reason, stack))
  defp log(_status, _kind, _reason, _stack),
    do: :ok

  ## Rendering

  require EEx
  EEx.function_from_file :defp, :template, "lib/plug/templates/debugger.eex", [:assigns]

  # Made public with @doc false for testing.
  @doc false
  def render(conn, status, kind, reason, stack, opts) do
    session = maybe_fetch_session(conn)
    params  = maybe_fetch_query_params(conn)
    {title, message} = info(kind, reason)
    conn = put_resp_content_type(conn, "text/html")
    send_resp conn, status, template(conn: conn, frames: frames(stack, opts),
                                     title: title, message: message,
                                     session: session, params: params)
  end

  defp maybe_fetch_session(conn) do
    if conn.private[:plug_session_fetch] do
      fetch_session(conn).private[:plug_session]
    end
  end

  defp maybe_fetch_query_params(conn) do
    fetch_query_params(conn).params
  end

  defp status(:error, error), do: Plug.Exception.status(error)
  defp status(_, _), do: 500

  defp info(:error, error),
    do: {inspect(error.__struct__), Exception.message(error)}
  defp info(:throw, thrown),
    do: {"unhandled throw", inspect(thrown)}
  defp info(:exit, reason),
    do: {"unhandled exit", Exception.format_exit(reason)}

  defp frames(stacktrace, opts) do
    app    = opts[:otp_app]
    editor = System.get_env("PLUG_EDITOR")

    stacktrace
    |> Enum.map_reduce(0, &each_frame(&1, &2, app, editor))
    |> elem(0)
  end

  defp each_frame(entry, index, root, editor) do
    {module, info, location, app, func, args} = get_entry(entry)
    {file, line} = {to_string(location[:file] || "nofile"), location[:line]}

    source  = get_source(module, file)
    context = get_context(root, app)
    snippet = get_snippet(source, line)

    {%{app: app,
       info: info,
       file: file,
       line: line,
       context: context,
       snippet: snippet,
       index: index,
       func: func,
       args: args,
       link: editor && get_editor(source, line, editor)
     }, index + 1}
  end

  # From :elixir_compiler_*
  defp get_entry({module, :__MODULE__, 0, location}) do
    {module, inspect(module) <> " (module)", location, get_app(module), nil, []}
  end

  # From :elixir_compiler_*
  defp get_entry({_module, :__MODULE__, 1, location}) do
    {nil, "(module)", location, nil, nil, []}
  end

  # From :elixir_compiler_*
  defp get_entry({_module, :__FILE__, 1, location}) do
    {nil, "(file)", location, nil, nil, []}
  end

  defp get_entry({module, fun, args, location}) when is_list(args) do
    {module, Exception.format_mfa(module, fun, length(args)), location, get_app(module), fun, args}
  end

  defp get_entry({module, fun, arity, location}) do
    {module, Exception.format_mfa(module, fun, arity), location, get_app(module), fun, []}
  end

  defp get_entry({fun, arity, location}) do
    {nil, Exception.format_fa(fun, arity), location, nil, fun, []}
  end

  defp get_app(module) do
    case :application.get_application(module) do
      {:ok, app} -> app
      :undefined -> nil
    end
  end

  defp get_context(app, app) when app != nil, do: :app
  defp get_context(_app1, _app2),             do: :all

  defp get_source(module, file) do
    cond do
      File.regular?(file) ->
        file
      Code.ensure_loaded?(module) &&
        (source = module.module_info(:compile)[:source]) ->
        to_string(source)
      true ->
        file
    end
  end

  defp get_editor(file, line, editor) do
    editor
    |> :binary.replace("__FILE__", URI.encode(Path.expand(file)))
    |> :binary.replace("__LINE__", to_string(line))
    |> h
  end

  @radius 5

  defp get_snippet(file, line) do
    if File.regular?(file) and is_integer(line) do
      to_discard = max(line - @radius - 1, 0)
      lines = File.stream!(file) |> Stream.take(line + 5) |> Stream.drop(to_discard)

      {first_five, lines} = Enum.split(lines, line - to_discard - 1)
      first_five = with_line_number first_five, to_discard + 1, false

      {center, last_five} = Enum.split(lines, 1)
      center = with_line_number center, line, true
      last_five = with_line_number last_five, line + 1, false

      first_five ++ center ++ last_five
    end
  end

  defp with_line_number(lines, initial, highlight) do
    Enum.map_reduce(lines, initial, fn(line, acc) ->
      {{acc, line, highlight}, acc + 1}
    end) |> elem(0)
  end

  ## Helpers

  defp method(%Plug.Conn{method: method}), do:
    method

  defp url(%Plug.Conn{scheme: scheme, host: host, port: port} = conn), do:
    "#{scheme}://#{host}:#{port}#{conn.request_path}"

  defp peer(%Plug.Conn{peer: {host, port}}), do:
    "#{:inet_parse.ntoa host}:#{port}"

  defp h(string) do
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
