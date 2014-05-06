# Plug

[![Build Status](https://travis-ci.org/elixir-lang/plug.png?branch=master)](https://travis-ci.org/elixir-lang/plug)

Plug is:

1. A specification for composable modules in between web applications
2. Connection adapters for different web servers in the Erlang VM

[Documentation for Plug is available online](http://elixir-lang.org/docs/plug/).

## Hello world

```elixir
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

IO.puts "Running MyPlug with Cowboy on http://localhost:4000"
Plug.Adapters.Cowboy.http MyPlug, []
```

The snippet above shows a very simple example on how to use Plug. Save that snippet to a file and run it inside the plug application with:

    mix run --no-halt path/to/file.exs

Access "http://localhost:4000" and we are done!

## Installation

You can use plug in your projects in two steps:

1. Add plug and your webserver of choice (currently cowboy) to your `mix.exs` dependencies:

    ```elixir
    def deps do
      [{:cowboy, github: "extend/cowboy"},
       {:plug, "~> 0.4.2"}]
    end
    ```

2. List both `:cowboy` and `:plug` as your application dependencies:

    ```elixir
    def application do
      [applications: [:cowboy, :plug]]
    end
    ```

Note: if you are using Elixir master, please use Plug master (from git) as well.

## The Plug.Conn

In the hello world example, we defined our first plug. What is a plug after all?

A plug takes two shapes. It is a function that receives a connection and a set of options as arguments and returns the connection or it is a module that provides an `init/1` function to initialize options and implement the `call/2` function, receiving the connection and the initialized options, and returning the connection.

As per the specification above, a connection is represented by the `Plug.Conn` record ([docs](http://elixir-lang.org/docs/plug/Plug.Conn.html)):

```elixir
%Plug.Conn{host: "www.example.com",
           path_info: ["bar", "baz"],
           ...}
```

Data can be read directly from the record and also pattern matched on. However, whenever you need to manipulate the record, you must use the functions defined in the `Plug.Conn` module ([docs](http://elixir-lang.org/docs/plug/Plug.Conn.html)). In our example, both `put_resp_content_type/2` and `send_resp/3` are defined in `Plug.Conn`.

Remember that, as everything else in Elixir, **a connection is immutable**, so every manipulation returns a new copy of the connection:

```elixir
conn = put_resp_content_type(conn, "text/plain")
conn = send_resp(conn, 200, "ok")
conn
```

Finally, keep in mind that a connection is a **direct interface to the underlying web server**. When you call `send_resp/3` above, it will immediately send the given status and body back to the client. This makes features like streaming a breeze to work with.

## Testing plugs and applications

Plug ships with a `Plug.Test` module ([docs](http://elixir-lang.org/docs/plug/Plug.Test.html)) that makes testing your plugs easy. Here is how we can test our hello world example:

```elixir
defmodule MyPlugTest do
  use ExUnit.Case, async: true
  use Plug.Test

  @opts MyPlug.init([])

  test "returns hello world" do
    # Create a test connection
    conn = conn(:get, "/")

    # Invoke the plug
    conn = MyPlug.call(conn, @opts)

    # Assert the response and status
    assert conn.state == :sent
    assert conn.status == 200
    assert conn.resp_body == "Hello world"
  end
end
```

## The Plug Router

The Plug router allows developers to quickly match on incoming requests and perform some action:

```elixir
defmodule AppRouter do
  import Plug.Conn
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
```

The router is a plug, which means it can be invoked as:

```elixir
AppRouter.call(conn, AppRouter.init([]))
```

Each route needs to return the connection as per the Plug specification.

Note `Plug.Router` compiles all of your routes into a single function and relies on the Erlang VM to optimize the underlying routes into a tree lookup, instead of a linear lookup that would instead match route-per-route. This means route lookups are extremely fast in Plug!

This also means that a catch all `match` is recommended to be defined, as in the example above, otherwise routing fails with a function clause error (as it would in any regular Elixir function).

### Available Plugs

This project aims to ship with different plugs that can be re-used accross applications:

* `Plug.Head` ([docs](http://elixir-lang.org/docs/plug/Plug.Head.html)) - converts HEAD requests to GET requests;
* `Plug.MethodOverride` ([docs](http://elixir-lang.org/docs/plug/Plug.MethodOverride.html)) - overrides a request method with one specified in headers;
* `Plug.Parsers` ([docs](http://elixir-lang.org/docs/plug/Plug.Parsers.html)) - responsible for parsing the request body given its content-type;
* `Plug.Session` ([docs](http://elixir-lang.org/docs/plug/Plug.Session.html)) - handles session management and storage;
* `Plug.Static` ([docs](http://elixir-lang.org/docs/plug/Plug.Static.html)) - serves static files;

## License

Plug source code is released under Apache 2 License.
Check LICENSE file for more information.
