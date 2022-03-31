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

  Each route receives a `conn` variable containing a `Plug.Conn`
  struct and it needs to return a connection, as per the Plug spec.
  A catch-all `match` is recommended to be defined as in the example
  above, otherwise routing fails with a function clause error.

  The router is itself a plug, which means it can be invoked as:

      AppRouter.call(conn, AppRouter.init([]))

  Each `Plug.Router` has a plug pipeline, defined by `Plug.Builder`,
  and by default it requires two plugs: `:match` and `:dispatch`.
  `:match` is responsible for finding a matching route which is
  then forwarded to `:dispatch`. This means users can easily hook
  into the router mechanism and add behaviour before match, before
  dispatch, or after both. See the `Plug.Builder` module for more
  information.

  ## Routes

      get "/hello" do
        send_resp(conn, 200, "world")
      end

  In the example above, a request will only match if it is a `GET`
  request and the route is "/hello". The supported HTTP methods are
  `get`, `post`, `put`, `patch`, `delete` and `options`.

  A route can also specify parameters which will then be available
  in the function body:

      get "/hello/:name" do
        send_resp(conn, 200, "hello #{name}")
      end

  This means the name can also be used in guards:

      get "/hello/:name" when name in ~w(foo bar) do
        send_resp(conn, 200, "hello #{name}")
      end

  The `:name` parameter will also be available in the function body as
  `conn.params["name"]` and `conn.path_params["name"]`.

  The identifier always starts with `:` and must be followed by letters,
  numbers, and underscores, like any Elixir variable. It is possible for
  identifiers to be either prefixed or suffixed by other words. For example,
  you can include a suffix such as a dot delimited file extension:

      get "/hello/:name.json" do
        send_resp(conn, 200, "hello #{name}")
      end

  The above will match `/hello/foo.json` but not `/hello/foo`.
  Other delimiters such as `-`, `@` may be used to denote suffixes.

  Routes allow for globbing which will match the remaining parts
  of a route. A glob match is done with the `*` character followed
  by the variable name. Typically you prefix the variable name with
  underscore to discard it:

      get "/hello/*_rest" do
        send_resp(conn, 200, "matches all routes starting with /hello")
      end

  But you can also assign the glob to any variable. The contents will
  always be a list:

      get "/hello/*glob" do
        send_resp(conn, 200, "route after /hello: #{inspect glob}")
      end

  Opposite to `:identifiers`, globs do not allow prefix nor suffix
  matches.

  Finally, a general `match` function is also supported:

      match "/hello" do
        send_resp(conn, 200, "world")
      end

  A `match` will match any route regardless of the HTTP method.
  Check `match/3` for more information on how route compilation
  works and a list of supported options.

  ## Parameter Parsing

  Handling request data can be done through the
  [`Plug.Parsers`](https://hexdocs.pm/plug/Plug.Parsers.html#content) plug. It
  provides support for parsing URL-encoded, form-data, and JSON data as well as
  providing a behaviour that others parsers can adopt.

  Here is an example of `Plug.Parsers` can be used in a `Plug.Router` router to
  parse the JSON-encoded body of a POST request:

      defmodule AppRouter do
        use Plug.Router

        plug :match

        plug Plug.Parsers,
             parsers: [:json],
             pass:  ["application/json"],
             json_decoder: Jason

        plug :dispatch

        post "/hello" do
          IO.inspect conn.body_params # Prints JSON POST body
          send_resp(conn, 200, "Success!")
        end
      end

  It is important that `Plug.Parsers` is placed before the `:dispatch` plug in
  the pipeline, otherwise the matched clause route will not receive the parsed
  body in its `Plug.Conn` argument when dispatched.

  `Plug.Parsers` can also be plugged between `:match` and `:dispatch` (like in
  the example above): this means that `Plug.Parsers` will run only if there is a
  matching route. This can be useful to perform actions such as authentication
  *before* parsing the body, which should only be parsed if a route matches
  afterwards.

  ## Error handling

  In case something goes wrong in a request, the router by default
  will crash, without returning any response to the client. This
  behaviour can be configured in two ways, by using two different
  modules:

  * `Plug.ErrorHandler` - allows the developer to customize exactly
    which page is sent to the client via the `handle_errors/2` function;

  * `Plug.Debugger` - automatically shows debugging and request information
    about the failure. This module is recommended to be used only in a
    development environment.

  Here is an example of how both modules could be used in an application:

      defmodule AppRouter do
        use Plug.Router

        if Mix.env == :dev do
          use Plug.Debugger
        end

        use Plug.ErrorHandler

        plug :match
        plug :dispatch

        get "/hello" do
          send_resp(conn, 200, "world")
        end

        defp handle_errors(conn, %{kind: _kind, reason: _reason, stack: _stack}) do
          send_resp(conn, conn.status, "Something went wrong")
        end
      end

  ## Passing data between routes and plugs

  It is also possible to assign data to the `Plug.Conn` that will
  be available to any plug invoked after the `:match` plug.
  This is very useful if you want a matched route to customize how
  later plugs will behave.

  You can use `:assigns` (which contains user data) or `:private`
  (which contains library/framework data) for this. For example:

      get "/hello", assigns: %{an_option: :a_value} do
        send_resp(conn, 200, "world")
      end

  In the example above, `conn.assigns[:an_option]` will be available
  to all plugs invoked after `:match`. Such plugs can read from
  `conn.assigns` (or `conn.private`) to configure their behaviour
  based on the matched route.

  ## `use` options

  All of the options given to `use Plug.Router` are forwarded to
  `Plug.Builder`. See the `Plug.Builder` module for more information.

  ## Telemetry

  The router emits the following telemetry events:

    * `[:plug, :router_dispatch, :start]` - dispatched before dispatching to a matched route
      * Measurement: `%{system_time: System.system_time}`
      * Metadata: `%{telemetry_span_context: term(), conn: Plug.Conn.t, route: binary, router: module}`

    * `[:plug, :router_dispatch, :exception]` - dispatched after exceptions on dispatching a route
      * Measurement: `%{duration: native_time}`
      * Metadata: `%{telemetry_span_context: term(), conn: Plug.Conn.t, route: binary, router: module, kind: :throw | :error | :exit, reason: term(), stacktrace: list()}`

    * `[:plug, :router_dispatch, :stop]` - dispatched after successfully dispatching a matched route
      * Measurement: `%{duration: native_time}`
      * Metadata: `%{telemetry_span_context: term(), conn: Plug.Conn.t, route: binary, router: module}`

  """

  @doc false
  defmacro __using__(opts) do
    quote location: :keep do
      import Plug.Router
      @plug_router_to %{}
      @before_compile Plug.Router

      use Plug.Builder, unquote(opts)

      @doc false
      def match(conn, _opts) do
        do_match(conn, conn.method, Plug.Router.Utils.decode_path_info!(conn), conn.host)
      end

      @doc false
      def dispatch(%Plug.Conn{} = conn, opts) do
        {path, fun} = Map.fetch!(conn.private, :plug_route)

        try do
          :telemetry.span(
            [:plug, :router_dispatch],
            %{conn: conn, route: path, router: __MODULE__},
            fn ->
              conn = fun.(conn, opts)
              {conn, %{conn: conn, route: path, router: __MODULE__}}
            end
          )
        catch
          kind, reason ->
            Plug.Conn.WrapperError.reraise(conn, kind, reason, __STACKTRACE__)
        end
      end

      defoverridable match: 2, dispatch: 2
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    unless Module.defines?(env.module, {:do_match, 4}) do
      raise "no routes defined in module #{inspect(env.module)} using Plug.Router"
    end

    router_to = Module.get_attribute(env.module, :plug_router_to)
    init_mode = Module.get_attribute(env.module, :plug_builder_opts)[:init_mode]

    defs =
      for {callback, {mod, opts}} <- router_to do
        if init_mode == :runtime do
          quote do
            defp unquote(callback)(conn, _opts) do
              unquote(mod).call(conn, unquote(mod).init(unquote(Macro.escape(opts))))
            end
          end
        else
          opts = mod.init(opts)

          quote do
            defp unquote(callback)(conn, _opts) do
              require unquote(mod)
              unquote(mod).call(conn, unquote(Macro.escape(opts)))
            end
          end
        end
      end

    quote do
      unquote_splicing(defs)
      import Plug.Router, only: []
    end
  end

  @doc """
  Returns the path of the route that the request was matched to.
  """
  @spec match_path(Plug.Conn.t()) :: String.t()
  def match_path(%Plug.Conn{} = conn) do
    {path, _fun} = Map.fetch!(conn.private, :plug_route)
    path
  end

  ## Match

  @doc """
  Main API to define routes.

  It accepts an expression representing the path and many options
  allowing the match to be configured.

  The route can dispatch either to a function body or a Plug module.

  ## Examples

      match "/foo/bar", via: :get do
        send_resp(conn, 200, "hello world")
      end

      match "/baz", to: MyPlug, init_opts: [an_option: :a_value]

  ## Options

  `match/3` and the other route macros accept the following options:

    * `:host` - the host which the route should match. Defaults to `nil`,
      meaning no host match, but can be a string like "example.com" or a
      string ending with ".", like "subdomain." for a subdomain match.

    * `:private` - assigns values to `conn.private` for use in the match

    * `:assigns` - assigns values to `conn.assigns` for use in the match

    * `:via` - matches the route against some specific HTTP method(s) specified
      as an atom, like `:get` or `:put`, or a list, like `[:get, :post]`.

    * `:do` - contains the implementation to be invoked in case
      the route matches.

    * `:to` - a Plug that will be called in case the route matches.

    * `:init_opts` - the options for the target Plug given by `:to`.

  A route should specify only one of `:do` or `:to` options.
  """
  defmacro match(path, options, contents \\ []) do
    compile(nil, path, options, contents, __CALLER__)
  end

  @doc """
  Dispatches to the path only if the request is a GET request.
  See `match/3` for more examples.
  """
  defmacro get(path, options, contents \\ []) do
    compile(:get, path, options, contents, __CALLER__)
  end

  @doc """
  Dispatches to the path only if the request is a HEAD request.
  See `match/3` for more examples.
  """
  defmacro head(path, options, contents \\ []) do
    compile(:head, path, options, contents, __CALLER__)
  end

  @doc """
  Dispatches to the path only if the request is a POST request.
  See `match/3` for more examples.
  """
  defmacro post(path, options, contents \\ []) do
    compile(:post, path, options, contents, __CALLER__)
  end

  @doc """
  Dispatches to the path only if the request is a PUT request.
  See `match/3` for more examples.
  """
  defmacro put(path, options, contents \\ []) do
    compile(:put, path, options, contents, __CALLER__)
  end

  @doc """
  Dispatches to the path only if the request is a PATCH request.
  See `match/3` for more examples.
  """
  defmacro patch(path, options, contents \\ []) do
    compile(:patch, path, options, contents, __CALLER__)
  end

  @doc """
  Dispatches to the path only if the request is a DELETE request.
  See `match/3` for more examples.
  """
  defmacro delete(path, options, contents \\ []) do
    compile(:delete, path, options, contents, __CALLER__)
  end

  @doc """
  Dispatches to the path only if the request is an OPTIONS request.
  See `match/3` for more examples.
  """
  defmacro options(path, options, contents \\ []) do
    compile(:options, path, options, contents, __CALLER__)
  end

  @doc """
  Forwards requests to another Plug. The `path_info` of the forwarded
  connection will exclude the portion of the path specified in the
  call to `forward`. If the path contains any parameters, those will
  be available in the target Plug in `conn.params` and `conn.path_params`.

  ## Options

  `forward` accepts the following options:

    * `:to` - a Plug the requests will be forwarded to.
    * `:init_opts` - the options for the target Plug. It is the preferred
      mechanism for passing options to the target Plug.
    * `:host` - a string representing the host or subdomain, exactly like in
      `match/3`.
    * `:private` - values for `conn.private`, exactly like in `match/3`.
    * `:assigns` - values for `conn.assigns`, exactly like in `match/3`.

  If `:init_opts` is undefined, then all remaining options are passed
  to the target plug.

  ## Examples

      forward "/users", to: UserRouter

  Assuming the above code, a request to `/users/sign_in` will be forwarded to
  the `UserRouter` plug, which will receive what it will see as a request to
  `/sign_in`.

      forward "/foo/:bar/qux", to: FooPlug

  Here, a request to `/foo/BAZ/qux` will be forwarded to the `FooPlug`
  plug, which will receive what it will see as a request to `/`,
  and `conn.params["bar"]` will be set to `"BAZ"`.

  Some other examples:

      forward "/foo/bar", to: :foo_bar_plug, host: "foobar."
      forward "/baz", to: BazPlug, init_opts: [plug_specific_option: true]

  """
  defmacro forward(path, options) do
    quote bind_quoted: [path: path, options: options] do
      {target, options} = Keyword.pop(options, :to)
      {options, plug_options} = Keyword.split(options, [:via, :host, :private, :assigns])
      plug_options = Keyword.get(plug_options, :init_opts, plug_options)

      if is_nil(target) or not is_atom(target) do
        raise ArgumentError, message: "expected :to to be an alias or an atom"
      end

      {target, target_opts} =
        case Atom.to_string(target) do
          "Elixir." <> _ -> {target, target.init(plug_options)}
          _ -> {{__MODULE__, target}, plug_options}
        end

      @plug_forward_target target
      @plug_forward_opts target_opts

      # Delegate the matching to the match/3 macro along with the options
      # specified by Keyword.split/2.
      match path <> "/*glob", options do
        Plug.forward(
          var!(conn),
          var!(glob),
          @plug_forward_target,
          @plug_forward_opts
        )
      end
    end
  end

  ## Match Helpers

  @doc false
  def __route__(method, path, guards, options) do
    {method, guards} = build_methods(List.wrap(method || options[:via]), guards)
    {params, match, guards, post_match} = Plug.Router.Utils.build_path_clause(path, guards)
    params = Plug.Router.Utils.build_path_params_match(params)
    private = extract_merger(options, :private)
    assigns = extract_merger(options, :assigns)
    host_match = Plug.Router.Utils.build_host_match(options[:host])
    {quote(do: conn), method, match, post_match, params, host_match, guards, private, assigns}
  end

  @doc false
  def __put_route__(conn, path, fun) do
    Plug.Conn.put_private(conn, :plug_route, {append_match_path(conn, path), fun})
  end

  defp append_match_path(%Plug.Conn{private: %{plug_route: {base_path, _}}}, path) do
    base_path <> path
  end

  defp append_match_path(%Plug.Conn{}, path) do
    path
  end

  # Entry point for both forward and match that is actually
  # responsible to compile the route.
  defp compile(method, expr, options, contents, caller) do
    {callback, options} =
      cond do
        Keyword.has_key?(contents, :do) ->
          {wrap_function_do(contents[:do]), expand_options(options, caller)}

        Keyword.has_key?(options, :do) ->
          {body, options} = Keyword.pop(options, :do)
          {wrap_function_do(body), expand_options(options, caller)}

        options[:to] ->
          options = expand_options(options, caller)

          callback =
            quote unquote: false do
              &(unquote(callback) / 2)
            end

          options =
            quote do
              {callback, options} = Plug.Router.__to__(unquote(caller.module), unquote(options))
              options
            end

          {callback, options}

        true ->
          raise ArgumentError, message: "expected one of :to or :do to be given as option"
      end

    {path, guards} = extract_path_and_guards(expr)

    quote bind_quoted: [
            method: method,
            path: path,
            options: options,
            guards: Macro.escape(guards, unquote: true),
            callback: Macro.escape(callback, unquote: true)
          ] do
      route = Plug.Router.__route__(method, path, guards, options)
      {conn, method, match, post_match, params, host, guards, private, assigns} = route

      defp do_match(unquote(conn), unquote(method), unquote(match), unquote(host))
           when unquote(guards) do
        unquote_splicing(post_match)
        unquote(private)
        unquote(assigns)

        params = unquote({:%{}, [], params})

        merge_params = fn
          %Plug.Conn.Unfetched{} -> params
          fetched -> Map.merge(fetched, params)
        end

        conn = update_in(unquote(conn).params, merge_params)
        conn = update_in(conn.path_params, merge_params)

        Plug.Router.__put_route__(conn, unquote(path), unquote(callback))
      end
    end
  end

  @doc false
  def __to__(module, options) do
    {to, options} = Keyword.pop(options, :to)
    {init_opts, options} = Keyword.pop(options, :init_opts, [])

    router_to = Module.get_attribute(module, :plug_router_to)
    callback = :"plug_router_to_#{map_size(router_to)}"
    router_to = Map.put(router_to, callback, {to, init_opts})
    Module.put_attribute(module, :plug_router_to, router_to)
    {Macro.var(callback, nil), options}
  end

  defp wrap_function_do(body) do
    quote do
      fn var!(conn), var!(opts) ->
        _ = var!(opts)
        unquote(body)
      end
    end
  end

  defp expand_options(opts, caller) do
    if Macro.quoted_literal?(opts) do
      Macro.prewalk(opts, &expand_alias(&1, caller))
    else
      opts
    end
  end

  defp expand_alias({:__aliases__, _, _} = alias, env),
    do: Macro.expand(alias, %{env | function: {:init, 1}})

  defp expand_alias(other, _env), do: other

  defp extract_merger(options, key) when is_list(options) do
    if option = Keyword.get(options, key) do
      quote do
        conn = update_in(conn.unquote(key), &Map.merge(&1, unquote(Macro.escape(option))))
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
    methods = Enum.map(methods, &Plug.Router.Utils.normalize_method(&1))
    var = quote do: method
    guards = join_guards(quote(do: unquote(var) in unquote(methods)), guards)
    {var, guards}
  end

  defp join_guards(fst, true), do: fst
  defp join_guards(fst, snd), do: quote(do: unquote(fst) and unquote(snd))

  # Extract the path and guards from the path.
  defp extract_path_and_guards({:when, _, [path, guards]}), do: {extract_path(path), guards}
  defp extract_path_and_guards(path), do: {extract_path(path), true}

  defp extract_path({:_, _, var}) when is_atom(var), do: "/*_path"
  defp extract_path(path), do: path
end
