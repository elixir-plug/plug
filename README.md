# Plug

Plug is:

1. A specification for composable modules in between web applications
2. A connection specification and adapters for different web servers in the Erlang VM

[![Build Status](https://travis-ci.org/elixir-lang/plug.png?branch=master)](https://travis-ci.org/elixir-lang/plug)

## Connection

A connection is represented by the `Plug.Conn` record:

```elixir
Plug.Conn[
  host: "www.example.com",
  path_info: ["bar", "baz"],
  assigns: [],
  ...
]
```

Most of the data can be read directly from the record, which is useful for pattern matching. Whenever you want to manipulate the connection, you must use the functions defined in `Plug.Connection`. As everything else in Elixir, **`Plug.Conn` is immutable**, so every manipulation returns a new copy of the connection:

```elixir
conn = assign(conn, :key, value)
conn = send(conn, 200, "OK!")
conn
```

Note the connection is a **direct interface to the underlying web server**. When you call `send/3` above, it will immediately send the given status and body back to the client.

## Available plugs

This project aims to ship with different plugs that can be re-used in different stacks:

* `Plug.Parsers` - a plug responsible for parsing the request body given its content-type;

## License

Plug source code is released under Apache 2 License.
Check LICENSE file for more information.
