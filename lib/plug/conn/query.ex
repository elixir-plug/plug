defmodule Plug.Conn.Query do
  @moduledoc """
  Conveniences for decoding and encoding url encoded queries.

  Plug allows a developer to build query strings
  that map to Elixir structures in order to make
  manipulation of such structures easier on the server
  side. Here are some examples:

      iex> decode("foo=bar")["foo"]
      "bar"

  If a value is given more than once, the last value takes precedence:

      iex> decode("foo=bar&foo=baz")["foo"]
      "baz"

  Nested structures can be created via `[key]`:

      iex> decode("foo[bar]=baz")["foo"]["bar"]
      "baz"

  Lists are created with `[]`:

      iex> decode("foo[]=bar&foo[]=baz")["foo"]
      ["bar", "baz"]

  Maps can be encoded:

      iex> encode(%{foo: "bar", baz: "bat"})
      "baz=bat&foo=bar"

  Encoding keyword lists preserves the order of the fields:

      iex> encode([foo: "bar", baz: "bat"])
      "foo=bar&baz=bat"

  When encoding keyword lists with duplicate keys, the key that comes first
  takes precedence:

      iex> encode([foo: "bar", foo: "bat"])
      "foo=bar"

  Encoding named lists:

      iex> encode(%{foo: ["bar", "baz"]})
      "foo[]=bar&foo[]=baz"

  Encoding nested structures:

      iex> encode(%{foo: %{bar: "baz"}})
      "foo[bar]=baz"

  """

  @doc """
  Decodes the given binary.

  The binary is assumed to be encoded in "x-www-form-urlencoded" format.
  The format is decoded and then validated for proper UTF-8 encoding.
  """
  def decode(
        query,
        initial \\ %{},
        invalid_exception \\ Plug.Conn.InvalidQueryError,
        validate_utf8 \\ true
      )

  def decode("", initial, _invalid_exception, _validate_utf8) do
    initial
  end

  def decode(query, initial, invalid_exception, validate_utf8) do
    parts = :binary.split(query, "&", [:global])

    Enum.reduce(
      Enum.reverse(parts),
      initial,
      &decode_www_pair(&1, &2, invalid_exception, validate_utf8)
    )
  end

  defp decode_www_pair("", acc, _invalid_exception, _validate_utf8) do
    acc
  end

  defp decode_www_pair(binary, acc, invalid_exception, validate_utf8) do
    current =
      case :binary.split(binary, "=") do
        [key, value] ->
          {decode_www_form(key, invalid_exception, validate_utf8),
           decode_www_form(value, invalid_exception, validate_utf8)}

        [key] ->
          {decode_www_form(key, invalid_exception, validate_utf8), nil}
      end

    decode_pair(current, acc)
  end

  defp decode_www_form(value, invalid_exception, validate_utf8) do
    try do
      URI.decode_www_form(value)
    rescue
      ArgumentError ->
        raise invalid_exception, "invalid urlencoded params, got #{value}"
    else
      binary ->
        if validate_utf8 do
          Plug.Conn.Utils.validate_utf8!(binary, invalid_exception, "urlencoded params")
        end

        binary
    end
  end

  @doc """
  Decodes the given tuple and stores it in the accumulator.

  It parses the key and stores the value into the current
  accumulator. The keys and values are not assumed to be
  encoded in "x-www-form-urlencoded".

  Parameter lists are added to the accumulator in reverse
  order, so be sure to pass the parameters in reverse order.
  """
  def decode_pair({key, value}, acc) do
    if key != "" and :binary.last(key) == ?] do
      # Remove trailing ]
      subkey = :binary.part(key, 0, byte_size(key) - 1)

      # Split the first [ then we will split on remaining ][.
      #
      #     users[address][street #=> [ "users", "address][street" ]
      #
      assign_split(:binary.split(subkey, "["), value, acc, :binary.compile_pattern("]["))
    else
      assign_map(acc, key, value)
    end
  end

  defp assign_split(["", rest], value, acc, pattern) do
    parts = :binary.split(rest, pattern)

    case acc do
      [_ | _] -> [assign_split(parts, value, :none, pattern) | acc]
      :none -> [assign_split(parts, value, :none, pattern)]
      _ -> acc
    end
  end

  defp assign_split([key, rest], value, acc, pattern) do
    parts = :binary.split(rest, pattern)

    case acc do
      %{^key => current} ->
        Map.put(acc, key, assign_split(parts, value, current, pattern))

      %{} ->
        Map.put(acc, key, assign_split(parts, value, :none, pattern))

      _ ->
        %{key => assign_split(parts, value, :none, pattern)}
    end
  end

  defp assign_split([""], nil, acc, _pattern) do
    case acc do
      [_ | _] -> acc
      _ -> []
    end
  end

  defp assign_split([""], value, acc, _pattern) do
    case acc do
      [_ | _] -> [value | acc]
      :none -> [value]
      _ -> acc
    end
  end

  defp assign_split([key], value, acc, _pattern) do
    assign_map(acc, key, value)
  end

  defp assign_map(acc, key, value) do
    case acc do
      %{^key => _} -> acc
      %{} -> Map.put(acc, key, value)
      _ -> %{key => value}
    end
  end

  @doc """
  Encodes the given map or list of tuples.
  """
  def encode(kv, encoder \\ &to_string/1) do
    IO.iodata_to_binary(encode_pair("", kv, encoder))
  end

  # covers structs
  defp encode_pair(field, %{__struct__: struct} = map, encoder) when is_atom(struct) do
    [field, ?= | encode_value(map, encoder)]
  end

  # covers maps
  defp encode_pair(parent_field, %{} = map, encoder) do
    encode_kv(map, parent_field, encoder)
  end

  # covers keyword lists
  defp encode_pair(parent_field, list, encoder) when is_list(list) and is_tuple(hd(list)) do
    encode_kv(Enum.uniq_by(list, &elem(&1, 0)), parent_field, encoder)
  end

  # covers non-keyword lists
  defp encode_pair(parent_field, list, encoder) when is_list(list) do
    mapper = fn
      value when is_map(value) and map_size(value) != 1 ->
        raise ArgumentError,
              "cannot encode maps inside lists when the map has 0 or more than 1 elements, " <>
                "got: #{inspect(value)}"

      value ->
        [?&, encode_pair(parent_field <> "[]", value, encoder)]
    end

    list
    |> Enum.flat_map(mapper)
    |> prune()
  end

  # covers nil
  defp encode_pair(field, nil, _encoder) do
    [field, ?=]
  end

  # encoder fallback
  defp encode_pair(field, value, encoder) do
    [field, ?= | encode_value(value, encoder)]
  end

  defp encode_kv(kv, parent_field, encoder) do
    mapper = fn
      {_, value} when value in [%{}, []] ->
        []

      {field, value} ->
        field =
          if parent_field == "" do
            encode_key(field)
          else
            parent_field <> "[" <> encode_key(field) <> "]"
          end

        [?&, encode_pair(field, value, encoder)]
    end

    kv
    |> Enum.flat_map(mapper)
    |> prune()
  end

  defp encode_key(item) do
    item |> to_string |> URI.encode_www_form()
  end

  defp encode_value(item, encoder) do
    item |> encoder.() |> URI.encode_www_form()
  end

  defp prune([?& | t]), do: t
  defp prune([]), do: []
end
