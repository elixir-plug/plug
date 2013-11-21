# Plug

[![Build Status](https://travis-ci.org/elixir-lang/plug.png?branch=master)](https://travis-ci.org/elixir-lang/plug)

Plug is:

1. A specification for composable modules in between web applications
2. Connection adapters for different web servers in the Erlang VM

## Hello world

```elixir
defmodule MyPlug do
  import Plug.Connection

  def call(conn, []) do
    conn = conn
           |> put_resp_content_type("text/plain")
           |> send(200, "Hello world")
    { :ok, conn }
  end
end

IO.puts "Running MyPlug with Cowboy on http://localhost:4000"
Plug.Adapters.Cowboy.http MyPlug, []
```

The snippet above shows a very simple example on how to use Plug. Save that snippet to a file and run it inside the plug application with:

    mix run --no-halt path/to/file.exs

Access "http://localhost:4000" and we are done!

## Installation

In practice, you want to use plugs in your existing projects. You can do that in two steps:

1. Add plug and your webserver of choice (currently cowboy) to your `mix.exs` dependencies:

    ```elixir
    def deps do
      [ { :cowboy, github: "extend/cowboy" },
        { :plug, PLUG_VERSION, github: "elixir-lang/plug" } ]
    end
    ```

2. List both `:cowboy` and `:plug` as your application dependencies:

    ```elixir
    def application do
      [ applications: [:cowboy, :plug] ]
    end
    ```

## The Plug Connection

In the hello world example, we defined our first plug. What is a plug after all?

> A plug is any function that receives a connection and a set of options as arguments and returns a tuple in the format `{ tag :: atom, conn :: Plug.Conn.t }`

As per the specification above, a connection is represented by the `Plug.Conn` record:

```elixir
Plug.Conn[host: "www.example.com",
          path_info: ["bar", "baz"],
          ...]
```

Data can be read directly from the record and also pattern matched on. However, whenever you need to manipulate the record, you must use the functions defined in the `Plug.Connection` module. In our example, both `put_resp_content_type/2` and `send/3` are defined in `Plug.Connection`.

Remember that, as everything else in Elixir, **a connection is immutable**, so every manipulation returns a new copy of the connection:

```elixir
conn = put_resp_content_type(conn, "text/plain")
conn = send(conn, 200, "ok")
conn
```

Finally, keep in mind that a connection is a **direct interface to the underlying web server**. When you call `send/3` above, it will immediately send the given status and body back to the client. This makes features like streaming a breeze to work with.

## Testing plugs and applications

Plug ships with a `Plug.Test` module that makes testing your plug applications easy. Here is how we can test our hello world example:

```elixir
defmodule MyPlugTest do
  use ExUnit.Case, async: true
  use Plug.Test

  test "returns hello world" do
    # Create a test connection
    conn = conn(:get, "/")

    # Invoke the plug
    { :ok, conn } = MyPlug.call(conn, [])

    # Assert the response and status
    assert conn.state == :sent
    assert conn.status == 200
    assert conn.resp_body == "Hello world"
  end
end
```

## The Plug Builder

Coming soon.

### Available Plugs

This project aims to ship with different plugs that can be re-used in different stacks:

* `Plug.Parsers` - a plug responsible for parsing the request body given its content-type;

## The Plug Router

Coming soon.

## License

Plug source code is released under Apache 2 License.
Check LICENSE file for more information.
