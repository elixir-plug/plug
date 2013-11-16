defmodule Plug.Connection.Query do
  @moduledoc """
  Conveniences for decoding and encoding query strings.

  Plug allows a developer to build query strings
  that maps to Elixir structures in order to make
  manipulation of such structures easier on the server
  side. Here are some examples:

      iex> decode("foo=bar")["foo"]
      "bar"

  If a value is given more than once, the first value is taken
  into account:

      iex> decode("foo=bar&foo=baz")["foo"]
      "bar"

  Nested structures can be created via `[key]`:

      iex> decode("foo[bar]=baz")["foo"]["bar"]
      "baz"

  Lists are created with `[]`:

      iex> decode("foo[]=bar&foo[]=baz")["foo"]
      ["bar", "baz"]

  """

  @doc """
  Decodes the given string.
  """
  def decode("") do
    []
  end

  def decode(query) do
    decoder = URI.query_decoder(query)
    Enum.reduce(Enum.reverse(decoder), [], &decode_pair(&1, &2))
  end

  @doc """
  Decodes the given tuple and store it in the accumulator.
  It parses the key and stores the value into te current
  accumulator.

  Parameters lists are added to the accumulator in reverse
  order, so be sure to pass the parameters in reverse order.
  """
  def decode_pair({ key, value }, acc) do
    parts =
      if key != "" and :binary.last(key) == ?] do
        # Remove trailing ]
        subkey = :binary.part(key, 0, byte_size(key) - 1)

        # Split the first [ then split remaining ][.
        #
        #     users[address][street #=> [ "users", "address][street" ]
        #
        case :binary.split(subkey, "[") do
          [key, subpart] ->
            [key|:binary.split(subpart, "][", [:global])]
          _ ->
            [key]
        end
      else
        [key]
      end

    assign_parts parts, acc, value
  end

  # We always assign the value in the last segment.
  # `age=17` would match here.
  defp assign_parts([key], acc, value) do
    put(key, value, acc)
  end

  # The current segment is a list. We simply prepend
  # the item to the list or create a new one if it does
  # not yet. This assumes that items are iterated in
  # reverse order.
  defp assign_parts([key,""|t], acc, value) do
    current =
      case :lists.keyfind(key, 1, acc) do
        { ^key, [h|t] } when not is_tuple(h) -> [h|t]
        _ -> []
      end

    if value = assign_list_parts(t, value) do
      put(key, [value|current], acc)
    else
      put(key, current, acc)
    end
  end

  # The current segment is a parent segment of a
  # dict. We need to create a dictionary and then
  # continue looping.
  defp assign_parts([key|t], acc, value) do
    child =
      case :lists.keyfind(key, 1, acc) do
        { ^key, [h|_] = val } when is_tuple(h) -> val
        _ -> []
      end

    put(key, assign_parts(t, child, value), acc)
  end

  defp assign_list_parts([], value), do: value
  defp assign_list_parts(t, value),  do: assign_parts(t, [], value)

  defp put(key, value, acc), do: [{ key, value }|:lists.keydelete(key, 1, acc)]
end