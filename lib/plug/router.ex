defmodule Plug.Router do
  @moduledoc ~S"""
  A DSL to define a routing algorithm that works with Plug.

  It provides a set of macros to generate routes. For example:

      defmodule AppRouter do
        use Plug.Router
        import Plug.Conn

        plug :match
        plug :dispatch

        get "/hello" do
          send_resp(conn, 200, "world")
        end

        match _ do
          send_resp(conn, 404, "oops")
        end
      end

  Each route needs to return a connection, as per the Plug spec.
  A catch all `match` is recommended to be defined, as in the example
  above, otherwise routing fails with a function clause error.

  The router is a plug, which means it can be invoked as:

      AppRouter.call(conn, [])

  Notice the router contains a plug stack and by default it requires
  two plugs: `match` and `dispatch`. `match` is responsible for
  finding a matching route which is then forwarded to `dispatch`.
  This means users can easily hook into the router mechanism and add
  behaviour before match, before dispatch or after both.

  ## Routes

      get "/hello" do
        send_resp(conn, 200, "world")
      end

  In the example above, a request will only match if it is
  a `GET` request and the route "/hello". The supported
  HTTP methods are `get`, `post`, `put`, `patch`, `delete`
  and `options`.

  A route can also specify parameters which will then be
  available in the function body:

      get "/hello/:name" do
        send_resp(conn, 200, "hello #{name}")
      end

  Routes allow for globbing which will match the remaining parts
  of a route and can be available as a parameter in the function
  body, also note that a glob can't be followed by other segments:

      get "/hello/*_rest" do
        send_resp(conn, 200, "matches all routes starting with /hello")
      end

      get "/hello/*glob" do
        send_resp(conn, 200, "route after /hello: #{inspect glob}")
      end

  Finally, a general `match` function is also supported:

      match "/hello" do
        send_resp(conn, 200, "world")
      end

  A `match` will match any route regardless of the HTTP method.
  Check `match/3` for more information on how route compilation
  works and a list of supported options.

  ## Routes compilation

  All routes are compiled to a match function that receives
  three arguments: the method, the request path split on "/"
  and the connection. Consider this example:

      match "/foo/bar", via: :get do
        send_resp(conn, 200, "hello world")
      end

  It is compiled to:

      defp match("GET", ["foo", "bar"], conn) do
        send_resp(conn, 200, "hello world")
      end

  This opens up a few possibilities. First, guards can be given
  to match:

      match "/foo/:bar" when size(bar) <= 3, via: :get do
        send_resp(conn, 200, "hello world")
      end

  Second, a list of splitten paths (which is the compiled result)
  is also allowed:

      match ["foo", bar], via: :get do
        send_resp(conn, 200, "hello world")
      end

  After a match is found, the block given as `do/end` is stored
  as a function in the connection. This function is then retrieved
  and invoked in the `dispatch` plug.
  """

  @doc false
  defmacro __using__(_) do
    quote location: :keep do
      import Plug.Builder, only: [plug: 1, plug: 2]
      import Plug.Router

      @behaviour Plug

      def init(opts) do
        opts
      end

      def match(conn, _opts) do
        Plug.Conn.assign_private(conn,
          :plug_route,
          do_match(conn.method, conn.path_info))
      end

      def dispatch(%Plug.Conn{assigns: assigns} = conn, _opts) do
        Map.get(conn.private, :plug_route).(conn)
      end

      defoverridable [init: 1, dispatch: 2]

      Module.register_attribute(__MODULE__, :plugs, accumulate: true)
      @before_compile Plug.Router
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    plugs = Module.get_attribute(env.module, :plugs)
    {conn, body} = Plug.Builder.compile(plugs)
    quote do
      import Plug.Router, only: []
      def call(unquote(conn), _), do: unquote(body)
    end
  end

  ## Match

  @doc """
  Main API to define routes. It accepts an expression representing
  the path and many options allowing the match to be configured.

  ## Examples

      match "/foo/bar", via: :get do
        send_resp(conn, 200, "hello world")
      end

  ## Options

  `match` accepts the following options:

  * `:via` - matches the route against some specific HTTP methods
  * `:do` - contains the implementation to be invoked in case
            the route matches

  """
  defmacro match(expression, options, contents \\ []) do
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

  @doc """
  Forwards requests to another Plug. The path_info of the forwarded
  connection will exclude the portion of the path specified in the
  call to `forward`.

  ## Examples

      forward "/users", to: UserRouter

  ## Options

  `forward` accepts the following options:

  * `:to` - a Plug where the requests will be forwarded

  All remaining options are passed to the underlying plug.
  """
  defmacro forward(path, options) when is_binary(path) do
    quote do
      {target, options} = Keyword.pop(unquote(options), :to)

      if nil?(target) or !is_atom(target) do
        raise ArgumentError, message: "expected :to to be an alias or an atom"
      end

      @plug_forward_target target
      @plug_forward_opts   target.init(options)

      match unquote(path <> "/*glob") do
        Plug.Router.Utils.forward(var!(conn), var!(glob), @plug_forward_target, @plug_forward_opts)
      end
    end
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

    {method, guard} = convert_methods(List.wrap(methods))
    {path, guards}  = extract_path_and_guards(expr, guard)
    {_vars, match}  = apply Plug.Router.Utils, builder, [Macro.expand(path, caller)]

    quote do
      defp do_match(unquote(method), unquote(match)) when unquote(guards) do
        fn var!(conn) -> unquote(body) end
      end
    end
  end

  # Convert the verbs given with :via into a variable
  # and guard set that can be added to the dispatch clause.
  defp convert_methods([]) do
    {quote(do: _), true}
  end

  defp convert_methods([method]) do
    {Plug.Router.Utils.normalize_method(method), true}
  end

  defp convert_methods(methods) do
    methods = Enum.map methods, &Plug.Router.Utils.normalize_method(&1)
    var = quote do: method
    {var, quote(do: unquote(var) in unquote(methods))}
  end

  # Extract the path and guards from the path.
  defp extract_path_and_guards({:when, _, [path, guards]}, true) do
    {path, guards}
  end

  defp extract_path_and_guards({:when, _, [path, guards]}, extra_guard) do
    {path, {:and, [], [guards, extra_guard]}}
  end

  defp extract_path_and_guards(path, extra_guard) do
    {path, extra_guard}
  end
end
