defmodule Plug.Router do
  @moduledoc ~S"""
  A DSL to define a routing algorithm that works with Plug.

  It provides a set of macros to generate routes. For example:

      defmodule AppRouter do
        use Plug.Router

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

      AppRouter.call(conn, AppRouter.init([]))

  Notice the router contains a plug pipeline and by default it requires
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

  ## Error handling

  In case something wents wrong in a request, the router allows
  the developer to customize what is rendered via the `handle_errors/2`
  callback:

      defmodule AppRouter do
        use Plug.Router

        plug :match
        plug :dispatch

        get "/hello" do
          send_resp(conn, 200, "world")
        end

        defp handle_errors(conn, %{kind: _kind, reason: _reason, stack: _stack}) do
          send_resp(conn, conn.status, "Something went wrong")
        end
      end

  The callback receives a connection and a map containing the exception
  kind (throw, error or exit), the reason (an exception for errors or
  a term for others) and the stacktrace. After the callback is invoked,
  the error is re-raised.

  It is advised to do as little work as possible when handling errors
  and avoid accessing data like parameters and session, as the parsing
  of those is what could have led the error to trigger in the first place.

  Also notice that those pages are going to be shown in production. If
  you are looking for error handling to help during development, consider
  using `Plug.Debugger`.

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
      import Plug.Router
      @before_compile Plug.Router

      use Plug.Builder

      defp match(conn, _opts) do
        Plug.Conn.put_private(conn,
          :plug_route,
          do_match(conn.method, conn.path_info, conn.host))
      end

      defp dispatch(%Plug.Conn{assigns: assigns} = conn, _opts) do
        Map.get(conn.private, :plug_route).(conn)
      end

      defp handle_errors(conn, assigns) do
        send_resp(conn, conn.status, "Something went wrong")
      end

      defoverridable [match: 2, dispatch: 2, handle_errors: 2]
    end
  end

  @doc false
  defmacro __before_compile__(_env) do
    quote do
      import Plug.Router, only: []

      defoverridable [call: 2]

      def call(conn, opts) do
        try do
          super(conn, opts)
        catch
          kind, reason ->
            Plug.Router.__catch__(conn, kind, reason, System.stacktrace, &handle_errors/2)
        end
      end
    end
  end

  @already_sent {:plug_conn, :sent}

  @doc false
  def __catch__(conn, kind, reason, stack, handle_errors) do
    receive do
      @already_sent ->
        send self(), @already_sent
    after
      0 ->
        reason = Exception.normalize(kind, reason, stack)

        conn
        |> Plug.Conn.put_status(status(kind, reason))
        |> handle_errors.(%{kind: kind, reason: reason, stack: stack})
    end

    :erlang.raise(kind, reason, stack)
  end

  defp status(:error, error),  do: Plug.Exception.status(error)
  defp status(:throw, _throw), do: 500
  defp status(:exit, _exit),   do: 500

  ## Match

  @doc """
  Main API to define routes.

  It accepts an expression representing the path and many options
  allowing the match to be configured.

  ## Examples

      match "/foo/bar", via: :get do
        send_resp(conn, 200, "hello world")
      end

  ## Options

  `match/3` and the others route macros accepts the following options:

    * `:host` - the host which the route should match. Defaults to `nil`,
      meaning no host match, but can be a string like "example.com" or a
      string ending with ".", like "subdomain." for a subdomain match

    * `:via` - matches the route against some specific HTTP methods

    * `:do` - contains the implementation to be invoked in case
      the route matches

  """
  defmacro match(path, options, contents \\ []) do
    compile(nil, path, options, contents)
  end

  @doc """
  Dispatches to the path only if it is get request.
  See `match/3` for more examples.
  """
  defmacro get(path, options, contents \\ []) do
    compile(:get, path, options, contents)
  end

  @doc """
  Dispatches to the path only if it is post request.
  See `match/3` for more examples.
  """
  defmacro post(path, options, contents \\ []) do
    compile(:post, path, options, contents)
  end

  @doc """
  Dispatches to the path only if it is put request.
  See `match/3` for more examples.
  """
  defmacro put(path, options, contents \\ []) do
    compile(:put, path, options, contents)
  end

  @doc """
  Dispatches to the path only if it is patch request.
  See `match/3` for more examples.
  """
  defmacro patch(path, options, contents \\ []) do
    compile(:patch, path, options, contents)
  end

  @doc """
  Dispatches to the path only if it is delete request.
  See `match/3` for more examples.
  """
  defmacro delete(path, options, contents \\ []) do
    compile(:delete, path, options, contents)
  end

  @doc """
  Dispatches to the path only if it is options request.
  See `match/3` for more examples.
  """
  defmacro options(path, options, contents \\ []) do
    compile(:options, path, options, contents)
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
  * `:host` - a string representing the host or subdomain, exactly like in
    `match/3`

  All remaining options are passed to the underlying plug.

      forward "/foo/bar", to: :foo_bar_plug, host: "foobar."
      forward "/api", to: ApiRouter, plug_specific_option: true
  """
  defmacro forward(path, options) when is_binary(path) do
    quote bind_quoted: [path: path, options: options] do
      {target, options}       = Keyword.pop(options, :to)
      {options, plug_options} = Keyword.split(options, [:host])

      if is_nil(target) or !is_atom(target) do
        raise ArgumentError, message: "expected :to to be an alias or an atom"
      end

      @plug_forward_target target
      @plug_forward_opts   target.init(plug_options)

      # Delegate the matching to the match/3 macro along with the options
      # specified by Keyword.split/2.
      match path <> "/*glob", options do
        Plug.Router.Utils.forward(
          var!(conn),
          var!(glob),
          @plug_forward_target,
          @plug_forward_opts
        )
      end
    end
  end

  @scopable_methods [
    :match,
    :forward,
    :get,
    :post,
    :put,
    :patch,
    :delete,
    :options,
  ]

  @doc """
  """
  defmacro scope(prefix, opts \\ [], do_block)

  # Multiple calls inside the block that gets passed to the `scope` macro
  # (identified by `:__block__`).
  defmacro scope(prefix, opts, do: {:__block__, metadata, methods}) do
    allowed_filter = fn({name, _, _}) -> name in @scopable_methods end

    unless Enum.all?(methods, allowed_filter) do
      raise ArgumentError, message: "Only these methods are allowed in a" <>
                                    "`scope` block: #{@scopable_methods}"
    end

    methods = Enum.map methods, fn(method) ->
      Plug.Router.Utils.scope_method(method, prefix, opts)
    end

    {:__block__, metadata, methods}
  end

  # Single call inside the block passed to `scope`. In this case, the quoted
  # expression that gets passed to `scope` is not a list of other calls but it's
  # the quoted call itself.
  defmacro scope(prefix, opts, do: method) do
    Plug.Router.Utils.scope_method(method, prefix, opts)
  end


  ## Match Helpers

  @doc false
  def __route__(method, path, guards, options) do
    {method, guards} = build_methods(List.wrap(method || options[:via]), guards)
    {_vars, match}   = Plug.Router.Utils.build_path_match(path)
    {method, match, Plug.Router.Utils.build_host_match(options[:host]), guards}
  end

  # Entry point for both forward and match that is actually
  # responsible to compile the route.
  defp compile(method, expr, options, contents) do
    {body, options} =
      cond do
        b = contents[:do] ->
          {b, options}
        options[:do] ->
          Keyword.pop(options, :do)
        true ->
          raise ArgumentError, message: "expected :do to be given as option"
      end

    {path, guards} = extract_path_and_guards(expr)

    quote bind_quoted: [method: method,
                        path: path,
                        options: options,
                        guards: Macro.escape(guards, unquote: true),
                        body: Macro.escape(body, unquote: true)] do
      {method, match, host, guards} = Plug.Router.__route__(method, path, guards, options)
      defp do_match(unquote(method), unquote(match), unquote(host)) when unquote(guards) do
        fn var!(conn) -> unquote(body) end
      end
    end
  end

  # Convert the verbs given with `:via` into a variable and guard set that can
  # be added to the dispatch clause.
  defp build_methods([], guards) do
    {quote(do: _), guards}
  end

  defp build_methods([method], guards) do
    {Plug.Router.Utils.normalize_method(method), guards}
  end

  defp build_methods(methods, guards) do
    methods = Enum.map methods, &Plug.Router.Utils.normalize_method(&1)
    var     = quote do: method
    guards  = join_guards(quote(do: unquote(var) in unquote(methods)), guards)
    {var, guards}
  end

  defp join_guards(fst, true), do: fst
  defp join_guards(fst, snd),  do: (quote do: unquote(fst) and unquote(snd))

  # Extract the path and guards from the path.
  defp extract_path_and_guards({:when, _, [path, guards]}), do: {extract_path(path), guards}
  defp extract_path_and_guards(path), do: {extract_path(path), true}

  defp extract_path({:_, _, var}) when is_atom(var), do: "/*_path"
  defp extract_path(path), do: path
end
