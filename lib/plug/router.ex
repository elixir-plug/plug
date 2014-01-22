defmodule Plug.Router do
  @moduledoc %S"""
  A DSL to define a routing algorithm that works with Plug.

  It provides a set of macros to generate routes. For example:

      defmodule AppRouter do
        use Plug.Router
        import Plug.Connection

        get "/hello" do
          { :ok, send_resp(conn, 200, "world") }
        end

        match _ do
          { :ok, send_resp(conn, 404, "oops") }
        end
      end

  The router is a plug, which means it can be invoked as:

      Plug.Router.call(conn, [])

  Each route needs to return `{ atom, conn }`, as per the Plug
  specification. A catch all `match` is recommended to be defined,
  as in the example above, otherwise routing fails with a function
  clause error.

  ## Routes

      get "/hello" do
        { :ok, send_resp(conn, 200, "world") }
      end

  In the example above, a request will only match if it is
  a `GET` request and the route "/hello". The supported
  HTTP methods are `get`, `post`, `put`, `patch`, `delete`
  and `options`.

  A route can also specify parameters which will then be
  available in the function body:

      get "/hello/:name" do
        { :ok, send_resp(conn, 200, "hello #{name}") }
      end

  Routes allow for globbing which will match the remaining parts
  of a route and can be available as a parameter in the function
  body, also note that a glob can't be followed by other segments:

      get "/hello/*" do
        { :ok, send_resp(conn, 200, "matches all routes starting with /hello") }
      end

      get "/hello/*glob" do
        { :ok, send_resp(conn, 200, "route after /hello: #{inspect glob}") }
      end

  Finally, a general `match` function is also supported:

      match "/hello" do
        { :ok, send_resp(conn, 200, "world")
      end

  A `match` will match any route regardless of the HTTP method.
  Check `match/3` for more information on how route compilation
  works and a list of supported options.
  """

  @doc false
  defmacro __using__(_) do
    quote location: :keep do
      import unquote(__MODULE__)

      def call(conn, _opts) do
        dispatch(conn.method, conn.path_info, conn)
      end

      defoverridable [call: 2]
    end
  end

  ## Match

  @doc """
  Main API to define routes. It accepts an expression representing
  the path and many options allowing the match to be configured.

  ## Examples

      match "/foo/bar", via: :get do
        { :ok, send_resp(conn, 200, "hello world") }
      end

  ## Options

  `match` accepts the following options:

  * `via:` matches the route against some specific HTTP methods
  * `do:` contains the implementation to be invoked in case
          the route matches

  ## Routes compilation

  All routes are compiled to a dispatch method that receives
  three arguments: the method, the request path split on "/"
  and the connection. Consider this example:

      match "/foo/bar", via: :get do
        { :ok, send_resp(conn, 200, "hello world") }
      end

  It is compiled to:

      def dispatch("GET", ["foo", "bar"], conn) do
        { :ok, send_resp(conn, 200, "hello world") }
      end

  This opens up a few possibilities. First, guards can be given
  to match:

      match "/foo/:bar" when size(bar) <= 3, via: :get do
        { :ok, send_resp(conn, 200, "hello world") }
      end

  Second, a list of splitten paths (which is the compiled result)
  is also allowed:

      match ["foo", bar], via: :get do
        { :ok, send_resp(conn, 200, "hello world") }
      end

  """
  defmacro match(expression, options, contents // []) do
    compile(:build_match, expression, Keyword.merge(contents, options), __CALLER__)
  end

  @doc """
  Dispatches to the path only if it is get request.
  See `match/3` for more examples.
  """
  defmacro get(path, contents) do
    compile(:build_match, path, Keyword.put(contents, :via, :get), __CALLER__)
  end

  @doc """
  Dispatches to the path only if it is post request.
  See `match/3` for more examples.
  """
  defmacro post(path, contents) do
    compile(:build_match, path, Keyword.put(contents, :via, :post), __CALLER__)
  end

  @doc """
  Dispatches to the path only if it is put request.
  See `match/3` for more examples.
  """
  defmacro put(path, contents) do
    compile(:build_match, path, Keyword.put(contents, :via, :put), __CALLER__)
  end

  @doc """
  Dispatches to the path only if it is patch request.
  See `match/3` for more examples.
  """
  defmacro patch(path, contents) do
    compile(:build_match, path, Keyword.put(contents, :via, :patch), __CALLER__)
  end

  @doc """
  Dispatches to the path only if it is delete request.
  See `match/3` for more examples.
  """
  defmacro delete(path, contents) do
    compile(:build_match, path, Keyword.put(contents, :via, :delete), __CALLER__)
  end

  @doc """
  Dispatches to the path only if it is options request.
  See `match/3` for more examples.
  """
  defmacro options(path, contents) do
    compile(:build_match, path, Keyword.put(contents, :via, :options), __CALLER__)
  end

  ## Match Helpers

  # Entry point for both forward and match that is actually
  # responsible to compile the route.
  defp compile(builder, expr, options, caller) do
    methods = options[:via]
    body    = options[:do]

    unless body do
      raise ArgumentError, message: "expected :do to be given as option"
    end

    methods_guard    = convert_methods(List.wrap(methods))
    { path, guards } = extract_path_and_guards(expr, default_guards(methods_guard))
    { _vars, match } = apply Plug.Router.Utils, builder, [Macro.expand(path, caller)]

    quote do
      def dispatch(method, unquote(match), var!(conn)) when unquote(guards), do: unquote(body)
    end
  end

  # Convert the verbs given with :via into a variable
  # and guard set that can be added to the dispatch clause.
  defp convert_methods([]) do
    true
  end

  defp convert_methods(methods) do
    methods = Enum.map methods, &Plug.Router.Utils.normalize_method(&1)
    quote do: method in unquote(methods)
  end

  # Extract the path and guards from the path.
  defp extract_path_and_guards({ :when, _, [path, guards] }, extra_guard) do
    { path, { :and, [], [guards, extra_guard] } }
  end

  defp extract_path_and_guards(path, extra_guard) do
    { path, extra_guard }
  end

  # Generate a default guard that is mean to avoid warnings
  # when the connection is not used. It automatically merges
  # the guards related to the method.
  defp default_guards(true) do
    default_guard
  end

  defp default_guards(other) do
    { :and, [], [other, default_guard] }
  end

  defp default_guard do
    quote do: is_tuple(var!(conn))
  end
end
