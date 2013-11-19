defmodule Plug.Connection.Query do
  @moduledoc """
  Conveniences for decoding and encoding query strings.

  Plug allows a developer to build query strings
  that maps to Elixir structures in order to make
  manipulation of such structures easier on the server
  side. Here are some examples:

      iex> decode("foo=bar")["foo"]
      "bar"

  If a value is given more than once, the last value wins:

      iex> decode("foo=bar&foo=baz")["foo"]
      "baz"

  Nested structures can be created via `[key]`:

      iex> decode("foo[bar]=baz")["foo"]["bar"]
      "baz"

  Lists are created with `[]`:

      iex> decode("foo[]=bar&foo[]=baz")["foo"]
      ["bar", "baz"]

  """

  @doc """
  Decodes the given binary.
  """
  def decode(query, initial // [])

  def decode("", initial) do
    initial
  end

  def decode(query, initial) do
    decoder = URI.query_decoder(query)
    Enum.reduce(Enum.reverse(decoder), initial, &decode_pair(&1, &2))
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

    assign_parts parts, value, acc
  end

  # We always assign the value in the last segment.
  # `age=17` would match here.
  defp assign_parts([key], value, acc) do
    case :lists.keyfind(key, 1, acc) do
      { _, _ } -> acc
      false -> put(key, value, acc)
    end
  end

  # The current segment is a list. We simply prepend
  # the item to the list or create a new one if it does
  # not yet. This assumes that items are iterated in
  # reverse order.
  defp assign_parts([key,""|t], value, acc) do
    case :lists.keyfind(key, 1, acc) do
      { ^key, [h|_] = current } when not is_tuple(h) ->
        replace(key, assign_list(t, current, value), acc)
      false ->
        put(key, assign_list(t, [], value), acc)
      _ ->
        acc
    end
  end

  # The current segment is a parent segment of a
  # dict. We need to create a dictionary and then
  # continue looping.
  defp assign_parts([key|t], value, acc) do
    case :lists.keyfind(key, 1, acc) do
      { ^key, [h|_] = current } when is_tuple(h) ->
        replace(key, assign_parts(t, value, current), acc)
      false ->
        put(key, assign_parts(t, value, []), acc)
      _ ->
        acc
    end
  end

  defp assign_list(t, current, value) do
    if value = assign_list(t, value), do: [value|current], else: current
  end

  defp assign_list([], value), do: value
  defp assign_list(t, value),  do: assign_parts(t, value, [])

  @compile { :inline, put: 3, replace: 3 }

  defp put(key, value, acc) do
    [{ key, value }|acc]
  end

  defp replace(key, value, acc) do
    [{ key, value }|:lists.keydelete(key, 1, acc)]
  end
end
