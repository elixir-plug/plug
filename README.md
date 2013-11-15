# Plug

Plug is:

1. A specification for composable modules in between web applications
2. A connection specification and adapters for different web servers in the Erlang VM

## Connection

A connection is represented by the `Plug.Conn` record:

```elixir
Plug.Conn[
  host: "www.example.com",
  path_info: ["bar", "baz"],
  script_name: ["foo"],
  assigns: [],
  ...
]
```

`Plug.Conn` is a record so it can be extended with protocols. Most of the data can be read directly from the record, which is useful for pattern matching. Whenever you want to manipulate the connection, you must use the functions defined in `Plug.Connection`.

As everything else in Elixir, **`Plug.Conn` is immutable**, so every manipulation returns a new copy of the connection:

```elixir
conn = assign(conn, :key, value)
conn = send(conn, 200, "OK!")
conn
```

Note the connection is a **direct interface to the underlying web server**. When you call `send/3` above, it will immediately send the given status and body back to the client. Furthermore, **parsing the request information is lazy**. For example, if you want to access the request headers, they need to be explicitly fetched before hand:

```elixir
conn = fetch(conn, :req_headers)
conn.req_headers["content-type"]
```

# License

Plug source code is released under Apache 2 License.
Check LICENSE file for more information.
