defmodule Plug.Parsers.URLENCODED do
  @moduledoc """
  Parses urlencoded request body.

  ## Options

  All options supported by `Plug.Conn.read_body/2` are also supported here.
  They are repeated here for convenience:

    * `:length` - sets the maximum number of bytes to read from the request,
      defaults to 1_000_000 bytes
    * `:read_length` - sets the amount of bytes to read at one time from the
      underlying socket to fill the chunk, defaults to 1_000_000 bytes
    * `:read_timeout` - sets the timeout for each socket read, defaults to
      15_000ms

  So by default, `Plug.Parsers` will read 1_000_000 bytes at a time from the
  socket with an overall limit of 8_000_000 bytes.
  """

  @behaviour Plug.Parsers

  def init(opts) do
    opts = Keyword.put_new(opts, :length, 1_000_000)
    Keyword.pop(opts, :body_reader, {Plug.Conn, :read_body, []})
  end

  def parse(conn, "application", "x-www-form-urlencoded", _headers, {{mod, fun, args}, opts}) do
    case apply(mod, fun, [conn, opts | args]) do
      {:ok, body, conn} ->
        validate_utf8 = Keyword.get(opts, :validate_utf8, true)

        {:ok,
         Plug.Conn.Query.decode(
           body,
           %{},
           Plug.Parsers.BadEncodingError,
           validate_utf8
         ), conn}

      {:more, _data, conn} ->
        {:error, :too_large, conn}

      {:error, :timeout} ->
        raise Plug.TimeoutError

      {:error, _} ->
        raise Plug.BadRequestError
    end
  end

  def parse(conn, _type, _subtype, _headers, _opts) do
    {:next, conn}
  end
end
