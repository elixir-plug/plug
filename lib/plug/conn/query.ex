defmodule Plug.Conn.Query do
  @moduledoc """
  Conveniences for decoding and encoding url encoded queries

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
  def decode(query, initial \\ %{})

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
  def decode_pair({key, value}, acc) do
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
    Map.put_new(acc, key, value)
  end

  # The current segment is a list. We simply prepend
  # the item to the list or create a new one if it does
  # not yet. This assumes that items are iterated in
  # reverse order.
  defp assign_parts([key,""|t], value, acc) do
    case Map.fetch(acc, key) do
      {:ok, current} when is_list(current) ->
        Map.put(acc, key, assign_list(t, current, value))
      :error ->
        Map.put(acc, key, assign_list(t, [], value))
      _ ->
        acc
    end
  end

  # The current segment is a parent segment of a
  # map. We need to create a map and then
  # continue looping.
  defp assign_parts([key|t], value, acc) do
    case Map.fetch(acc, key) do
      {:ok, %{} = current} ->
        Map.put(acc, key, assign_parts(t, value, current))
      :error ->
        Map.put(acc, key, assign_parts(t, value, %{}))
      _ ->
        acc
    end
  end

  defp assign_list(t, current, value) do
    if value = assign_list(t, value), do: [value|current], else: current
  end

  defp assign_list([], value), do: value
  defp assign_list(t, value),  do: assign_parts(t, value, %{})
end
