defmodule Plug.Conn.Query do
  @moduledoc """
  Conveniences for decoding and encoding URL-encoded queries.

  Plug allows developers to build query strings that map to
  Elixir structures in order to make manipulation of such structures
  easier on the server side. Here are some examples:

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

  > #### Nesting inside lists {: .error}
  >
  > Nesting inside lists is ambiguous and unspecified behaviour.
  > Therefore, you should not rely on the decoding behaviour of
  > `user[][foo]=1&user[][bar]=2`.
  >
  > As an alternative, you can explicitly specify the keys:
  >
  >     # If foo and bar belong to the same entry
  >     user[0][foo]=1&user[0][bar]=2
  >
  >     # If foo and bar are different entries
  >     user[0][foo]=1&user[1][bar]=2

  Keys without values are treated as empty strings,
  according to https://url.spec.whatwg.org/#application/x-www-form-urlencoded:

      iex> decode("foo")["foo"]
      ""

  Maps can be encoded:

      iex> encode(%{foo: "bar"})
      "foo=bar"

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

  It is only possible to encode maps inside lists if those maps have exactly one element.
  In this case it is possible to encode the parameters using maps instead of lists:

      iex> encode(%{"list" => [%{"a" => 1, "b" => 2}]})
      ** (ArgumentError) cannot encode maps inside lists when the map has 0 or more than 1 element, got: %{\"a\" => 1, \"b\" => 2}

      iex> encode(%{"list" => %{0 => %{"a" => 1, "b" => 2}}})
      "list[0][a]=1&list[0][b]=2"

  For stateful decoding, see `decode_init/0`, `decode_each/2`, and `decode_done/2`.
  """

  @typedoc """
  Stateful decoder accumulator.

  See `decode_init/0`, `decode_each/2`, and `decode_done/2`.
  """
  @typedoc since: "1.16.0"
  @opaque decoder() :: map()

  @doc """
  Decodes the given `query`.

  The `query` is assumed to be encoded in the "x-www-form-urlencoded" format.
  The format is decoded at first. Then, if `validate_utf8` is `true`, the decoded
  result is validated for proper UTF-8 encoding. `validate_utf8` may also be
  an atom with a custom exception to raise.

  `initial` is the initial "accumulator" where decoded values will be added.

  `invalid_exception` is the exception module for the exception to raise on
  errors with decoding.
  """
  @spec decode(String.t(), keyword(), module(), boolean()) :: %{optional(String.t()) => term()}
  def decode(
        query,
        initial \\ [],
        invalid_exception \\ Plug.Conn.InvalidQueryError,
        validate_utf8 \\ true
      )

  def decode("", initial, _invalid_exception, _validate_utf8) do
    Map.new(initial)
  end

  def decode(query, initial, invalid_exception, validate_utf8)
      when is_binary(query) do
    parts = :binary.split(query, "&", [:global])

    parts
    |> Enum.reduce(decode_init(), &decode_www_pair(&1, &2, invalid_exception, validate_utf8))
    |> decode_done(initial)
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
          {decode_www_form(key, invalid_exception, validate_utf8), ""}
      end

    decode_each(current, acc)
  end

  defp decode_www_form(value, invalid_exception, validate_utf8) do
    # TODO: Remove rescue as this can't fail from Elixir v1.13
    try do
      URI.decode_www_form(value)
    rescue
      ArgumentError ->
        raise invalid_exception, "invalid urlencoded params, got #{value}"
    else
      binary ->
        case validate_utf8 do
          true -> Plug.Conn.Utils.validate_utf8!(binary, invalid_exception, "urlencoded params")
          false -> :ok
          module -> Plug.Conn.Utils.validate_utf8!(binary, module, "urlencoded params")
        end

        binary
    end
  end

  @doc """
  Starts a stateful decoder.

  Use `decode_each/2` and `decode_done/2` to decode and complete.
  See `decode_each/2` for examples.
  """
  @spec decode_init() :: decoder()
  def decode_init(), do: %{root: []}

  @doc """
  Decodes the given `pair` tuple.

  It parses the key and stores the value into the current
  accumulator `decoder`. The keys and values are not assumed to be
  encoded in `"x-www-form-urlencoded"`.

  ## Examples

      iex> decoder = Plug.Conn.Query.decode_init()
      iex> decoder = Plug.Conn.Query.decode_each({"foo", "bar"}, decoder)
      iex> decoder = Plug.Conn.Query.decode_each({"baz", "bat"}, decoder)
      iex> Plug.Conn.Query.decode_done(decoder)
      %{"baz" => "bat", "foo" => "bar"}

  """
  @spec decode_each({term(), term()}, decoder()) :: decoder()
  def decode_each(pair, decoder)

  def decode_each({"", value}, map) do
    insert_keys([{:root, ""}], value, map)
  end

  def decode_each({key, value}, map) do
    # Examples:
    #
    #     users
    #     #=> [{:root, "users"}]
    #
    #     users[foo]
    #     #=> [{"users", "foo"}, {:root, "users"}]
    #
    #     users[foo][bar]
    #     #=> [{"users[foo]", "bar"}, {"users", "foo"}, {:root, "users"}]
    #
    keys =
      with ?] <- :binary.last(key),
           {pos, 1} when pos > 0 <- :binary.match(key, "[") do
        value = binary_part(key, 0, pos)
        pos = pos + 1
        rest = binary_part(key, pos, byte_size(key) - pos)
        split_keys(rest, key, pos, pos, value, [{:root, value}])
      else
        _ -> [{:root, key}]
      end

    insert_keys(keys, value, map)
  end

  defp split_keys(<<?], ?[, rest::binary>>, binary, current_pos, start_pos, level, acc) do
    value = split_key(binary, current_pos, start_pos)
    next_level = binary_part(binary, 0, current_pos + 1)
    split_keys(rest, binary, current_pos + 2, current_pos + 2, next_level, [{level, value} | acc])
  end

  defp split_keys(<<?]>>, binary, current_pos, start_pos, level, acc) do
    value = split_key(binary, current_pos, start_pos)
    [{level, value} | acc]
  end

  defp split_keys(<<_, rest::binary>>, binary, current_pos, start_pos, level, acc) do
    split_keys(rest, binary, current_pos + 1, start_pos, level, acc)
  end

  defp split_key(_binary, start, start), do: nil
  defp split_key(binary, current, start), do: binary_part(binary, start, current - start)

  defp insert_keys([{level, key} | rest], value, map) do
    case map do
      %{^level => entries} -> %{map | level => [{key, value} | entries]}
      %{} -> insert_keys(rest, [:pointer | level], Map.put(map, level, [{key, value}]))
    end
  end

  defp insert_keys([], _value, map) do
    map
  end

  @doc """
  Finishes stateful decoding and returns a map with the decoded pairs.

  `decoder` is the stateful decoder returned by `decode_init/0` and `decode_each/2`.
  `initial` is an enumerable of key-value pairs that functions as the initial
  accumulator for the returned map (see examples below).

  ## Examples

      iex> decoder = Plug.Conn.Query.decode_init()
      iex> decoder = Plug.Conn.Query.decode_each({"foo", "bar"}, decoder)
      iex> Plug.Conn.Query.decode_done(decoder, %{"initial" => true})
      %{"foo" => "bar", "initial" => true}

  """
  @spec decode_done(decoder(), Enumerable.t()) :: %{optional(String.t()) => term()}
  def decode_done(%{root: root} = decoder, initial \\ []) do
    finalize_map(root, Enum.to_list(initial), decoder)
  end

  defp finalize_pointer(key, map) do
    case Map.fetch!(map, key) do
      [{nil, _} | _] = entries -> finalize_list(entries, [], map)
      entries -> finalize_map(entries, [], map)
    end
  end

  defp finalize_map([{key, [:pointer | pointer]} | rest], acc, map),
    do: finalize_map(rest, [{key, finalize_pointer(pointer, map)} | acc], map)

  defp finalize_map([{nil, _} | rest], acc, map),
    do: finalize_map(rest, acc, map)

  defp finalize_map([{_, _} = kv | rest], acc, map),
    do: finalize_map(rest, [kv | acc], map)

  defp finalize_map([], acc, _map),
    do: Map.new(acc)

  defp finalize_list([{nil, [:pointer | pointer]} | rest], acc, map),
    do: finalize_list(rest, [finalize_pointer(pointer, map) | acc], map)

  defp finalize_list([{nil, value} | rest], acc, map),
    do: finalize_list(rest, [value | acc], map)

  defp finalize_list([{_, _} | rest], acc, map),
    do: finalize_list(rest, acc, map)

  defp finalize_list([], acc, _map),
    do: acc

  @doc """
  Decodes the given tuple and stores it in the given accumulator.

  It parses the key and stores the value into the current
  accumulator. The keys and values are not assumed to be
  encoded in "x-www-form-urlencoded".

  Parameter lists are added to the accumulator in reverse
  order, so be sure to pass the parameters in reverse order.
  """
  @deprecated "Use decode_init/0, decode_each/2, and decode_done/2 instead"
  def decode_pair({key, value} = _pair, acc) do
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
      %{^key => current} when is_list(current) or is_map(current) ->
        Map.put(acc, key, assign_split(parts, value, current, pattern))

      %{^key => _} ->
        acc

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
  @spec encode(Enumerable.t(), (term() -> binary())) :: binary()
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
              "cannot encode maps inside lists when the map has 0 or more than 1 element, " <>
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
