# Plug

[![Build Status](https://github.com/elixir-plug/plug/workflows/CI/badge.svg)](https://github.com/elixir-plug/plug/actions?query=workflow%3A%22CI%22)
[![hex.pm](https://img.shields.io/hexpm/v/plug.svg)](https://hex.pm/packages/plug)
[![hexdocs.pm](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/plug/)

Plug is:

  1. A specification for composing web applications with functions
  2. Connection adapters for different web servers in the Erlang VM

In other words, Plug allows you to build web applications from small pieces and run them on different web servers. Plug is used by web frameworks such as [Phoenix](https://phoenixframework.org) to manage requests, responses, and websockets. This documentation will show some high-level examples and introduce the Plug's main building blocks.

## Installation

In order to use Plug, you need a webserver and its bindings for Plug.
There are two options at the moment:

1. Use the Cowboy webserver (Erlang-based) by adding the `plug_cowboy` package to your `mix.exs`:

    ```elixir
    def deps do
      [
        {:plug_cowboy, "~> 2.0"}
      ]
    end
    ```

2. Use the Bandit webserver (Elixir-based) by adding the `bandit` package to your `mix.exs`:

    ```elixir
    def deps do
      [
        {:bandit, "~> 1.0"}
      ]
    end
    ```

## Hello world: request/response

This is a minimal hello world example, using the Cowboy webserver:

```elixir
Mix.install([:plug, :plug_cowboy])

defmodule MyPlug do
  import Plug.Conn

  def init(options) do
    # initialize options
    options
  end

  def call(conn, _opts) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "Hello world")
  end
end

require Logger
webserver = {Plug.Cowboy, plug: MyPlug, scheme: :http, options: [port: 4000]}
{:ok, _} = Supervisor.start_link([webserver], strategy: :one_for_one)
Logger.info("Plug now running on localhost:4000")
Process.sleep(:infinity)
```

Save that snippet to a file and execute it as `elixir hello_world.exs`.
Access <http://localhost:4000/> and you should be greeted!

In the example above, we wrote our first **module plug**, called `MyPlug`.
Module plugs must define the `init/1` function and the `call/2` function.
`call/2` is invoked with the connection and the options returned by `init/1`.

## Hello world: websockets

Plug v1.14 includes a connection `upgrade` API, which means it provides WebSocket
support out of the box. Let's see an example, this time using the Bandit webserver
and the `websocket_adapter` project for the WebSocket bits. Since we need different
routes, we will use the built-in `Plug.Router` for that:

```elixir
Mix.install([:bandit, :websock_adapter])

defmodule EchoServer do
  def init(options) do
    {:ok, options}
  end

  def handle_in({"ping", [opcode: :text]}, state) do
    {:reply, :ok, {:text, "pong"}, state}
  end

  def terminate(:timeout, state) do
    {:ok, state}
  end
end

defmodule Router do
  use Plug.Router

  plug Plug.Logger
  plug :match
  plug :dispatch

  get "/" do
    send_resp(conn, 200, """
    Use the JavaScript console to interact using websockets

    sock  = new WebSocket("ws://localhost:4000/websocket")
    sock.addEventListener("message", console.log)
    sock.addEventListener("open", () => sock.send("ping"))
    """)
  end

  get "/websocket" do
    conn
    |> WebSockAdapter.upgrade(EchoServer, [], timeout: 60_000)
    |> halt()
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end

require Logger
webserver = {Bandit, plug: Router, scheme: :http, port: 4000}
{:ok, _} = Supervisor.start_link([webserver], strategy: :one_for_one)
Logger.info("Plug now running on localhost:4000")
Process.sleep(:infinity)
```

Save that snippet to a file and execute it as `elixir websockets.exs`.
Access <http://localhost:4000/> and you should see messages in your browser
console.

This time, we used `Plug.Router`, which allows us to define the routes
used by our web application and a series of steps/plugs, such as
`plug Plug.Logger`, to be executed on every request.

Furthermore, as you can see, Plug abstracts the different webservers.
When booting up your application, the difference is between choosing
`Plug.Cowboy` or `Bandit`.

For now, we have directly started the server in a throw-away supervisor but,
for production deployments, you want to start them in application
supervision tree. See the [Supervised handlers](#supervised-handlers) section next.

## Supervised handlers

On a production system, you likely want to start your Plug pipeline under your application's supervision tree. Start a new Elixir project with the `--sup` flag:

```shell
$ mix new my_app --sup
```

Add `:plug_cowboy` (or `:bandit`) as a dependency to your `mix.exs`:

```elixir
def deps do
  [
    {:plug_cowboy, "~> 2.0"}
  ]
end
```

Now update `lib/my_app/application.ex` as follows:

```elixir
defmodule MyApp.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    # List all child processes to be supervised
    children = [
      {Plug.Cowboy, scheme: :http, plug: MyPlug, options: [port: 4001]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

Finally create `lib/my_app/my_plug.ex` with the `MyPlug` module.

Now run `mix run --no-halt` and it will start your application with a web server running at <http://localhost:4001>.

## Plugs and the `Plug.Conn` struct

In the hello world example, we defined our first plug called `MyPlug`. There are two types of plugs, module plugs and function plugs.

A module plug implements an `init/1` function to initialize the options and a `call/2` function which receives the connection and initialized options and returns the connection:

```elixir
defmodule MyPlug do
  def init([]), do: false
  def call(conn, _opts), do: conn
end
```

A function plug takes the connection, a set of options as arguments, and returns the connection:

```elixir
def hello_world_plug(conn, _opts) do
  conn
  |> put_resp_content_type("text/plain")
  |> send_resp(200, "Hello world")
end
```

A connection is represented by the `%Plug.Conn{}` struct:

```elixir
%Plug.Conn{
  host: "www.example.com",
  path_info: ["bar", "baz"],
  ...
}
```

Data can be read directly from the connection and also pattern matched on. Manipulating the connection often happens with the use of the functions defined in the `Plug.Conn` module. In our example, both `put_resp_content_type/2` and `send_resp/3` are defined in `Plug.Conn`.

Remember that, as everything else in Elixir, **a connection is immutable**, so every manipulation returns a new copy of the connection:

```elixir
conn = put_resp_content_type(conn, "text/plain")
conn = send_resp(conn, 200, "ok")
conn
```

Finally, keep in mind that a connection is a **direct interface to the underlying web server**. When you call `send_resp/3` above, it will immediately send the given status and body back to the client. This makes features like streaming a breeze to work with.

## `Plug.Router`

To write a "router" plug that dispatches based on the path and method of incoming requests, Plug provides `Plug.Router`:

```elixir
defmodule MyRouter do
  use Plug.Router

  plug :match
  plug :dispatch

  get "/hello" do
    send_resp(conn, 200, "world")
  end

  forward "/users", to: UsersRouter

  match _ do
    send_resp(conn, 404, "oops")
  end
end
```

The router is a plug. Not only that: it contains its own plug pipeline too. The example above says that when the router is invoked, it will invoke the `:match` plug, represented by a local (imported) `match/2` function, and then call the `:dispatch` plug which will execute the matched code.

Plug ships with many plugs that you can add to the router plug pipeline, allowing you to plug something before a route matches or before a route is dispatched to. For example, if you want to add logging to the router, just do:

```elixir
plug Plug.Logger
plug :match
plug :dispatch
```

Note `Plug.Router` compiles all of your routes into a single function and relies on the Erlang VM to optimize the underlying routes into a tree lookup, instead of a linear lookup that would instead match route-per-route. This means route lookups are extremely fast in Plug!

This also means that a catch all `match` block is recommended to be defined as in the example above, otherwise routing fails with a function clause error (as it would in any regular Elixir function).

Each route needs to return the connection as per the Plug specification. See the `Plug.Router` docs for more information.

## Testing plugs

Plug ships with a `Plug.Test` module that makes testing your plugs easy. Here is how we can test the router from above (or any other plug):

```elixir
defmodule MyPlugTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn
  
  @opts MyRouter.init([])

  test "returns hello world" do
    # Create a test connection
    conn = conn(:get, "/hello")

    # Invoke the plug
    conn = MyRouter.call(conn, @opts)

    # Assert the response and status
    assert conn.state == :sent
    assert conn.status == 200
    assert conn.resp_body == "world"
  end
end
```

## Available plugs

This project aims to ship with different plugs that can be re-used across applications:

  * `Plug.BasicAuth` - provides Basic HTTP authentication;
  * `Plug.CSRFProtection` - adds Cross-Site Request Forgery protection to your application. Typically required if you are using `Plug.Session`;
  * `Plug.Head` - converts HEAD requests to GET requests;
  * `Plug.Logger` - logs requests;
  * `Plug.MethodOverride` - overrides a request method with one specified in the request parameters;
  * `Plug.Parsers` - responsible for parsing the request body given its content-type;
  * `Plug.RequestId` - sets up a request ID to be used in logs;
  * `Plug.RewriteOn` - rewrite the request's host/port/protocol from `x-forwarded-*` headers;
  * `Plug.Session` - handles session management and storage;
  * `Plug.SSL` - enforces requests through SSL;
  * `Plug.Static` - serves static files;
  * `Plug.Telemetry` - instruments the plug pipeline with `:telemetry` events;

You can go into more details about each of them [in our docs](http://hexdocs.pm/plug/).

## Helper modules

Modules that can be used after you use `Plug.Router` or `Plug.Builder` to help development:

  * `Plug.Debugger` - shows a helpful debugging page every time there is a failure in a request;
  * `Plug.ErrorHandler` - allows developers to customize error pages in case of crashes instead of sending a blank one;

## Contributing

We welcome everyone to contribute to Plug and help us tackle existing issues!

Use the [issue tracker][issues] for bug reports or feature requests. Open a [pull request][pulls] when you are ready to contribute. When submitting a pull request you should not update the `CHANGELOG.md`.

If you are planning to contribute documentation, [please check our best practices for writing documentation][writing-docs].

Finally, remember all interactions in our official spaces follow our [Code of Conduct][code-of-conduct].

## Supported Versions

| Branch | Support                  |
|--------|--------------------------|
| v1.15  | Bug fixes                |
| v1.14  | Security patches only    |
| v1.13  | Security patches only    |
| v1.12  | Security patches only    |
| v1.11  | Security patches only    |
| v1.10  | Security patches only    |
| v1.9   | Unsupported from 10/2023 |
| v1.8   | Unsupported from 01/2023 |
| v1.7   | Unsupported from 01/2022 |
| v1.6   | Unsupported from 01/2022 |
| v1.5   | Unsupported from 03/2021 |
| v1.4   | Unsupported from 12/2018 |
| v1.3   | Unsupported from 12/2018 |
| v1.2   | Unsupported from 06/2018 |
| v1.1   | Unsupported from 01/2018 |
| v1.0   | Unsupported from 05/2017 |

## License

Plug source code is released under Apache License 2.0.
Check LICENSE file for more information.

  [issues]: https://github.com/elixir-plug/plug/issues
  [pulls]: https://github.com/elixir-plug/plug/pulls
  [code-of-conduct]: https://github.com/elixir-lang/elixir/blob/master/CODE_OF_CONDUCT.md
  [writing-docs]: https://hexdocs.pm/elixir/writing-documentation.html
