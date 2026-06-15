defmodule Plug.Conn.Cookies do
  @moduledoc """
  Conveniences for encoding and decoding cookies.
  """

  @doc false
  def sign_or_encrypt(%Plug.Conn{} = conn, key, value, opts) do
    {sign?, opts} = Keyword.pop(opts, :sign, false)
    {encrypt?, opts} = Keyword.pop(opts, :encrypt, false)

    case {sign?, encrypt?} do
      {true, true} ->
        raise ArgumentError,
              ":encrypt automatically implies :sign. Please pass only one or the other"

      {true, false} ->
        {Plug.Crypto.sign(conn.secret_key_base, key <> "_cookie", value, max_age(opts)), opts}

      {false, true} ->
        {Plug.Crypto.encrypt(conn.secret_key_base, key <> "_cookie", value, max_age(opts)), opts}

      {false, false} when is_binary(value) ->
        {value, opts}

      {false, false} ->
        raise ArgumentError, "cookie value must be a binary unless the cookie is signed/encrypted"
    end
  end

  defp max_age(opts) do
    max_age = Keyword.get(opts, :max_age) || 86400
    [keys: Plug.Keys, max_age: max_age]
  end

  @doc """
  Decodes the given cookies as given in either a request or response header.

  If a cookie is invalid, it is automatically discarded from the result.

  ## Examples

      iex> decode("key1=value1;key2=value2")
      %{"key1" => "value1", "key2" => "value2"}

  """
  def decode(cookie) when is_binary(cookie) do
    Map.new(decode_kv(cookie, []))
  end

  defp decode_kv("", acc), do: acc
  defp decode_kv(<<h, t::binary>>, acc) when h in [?\s, ?\t], do: decode_kv(t, acc)
  defp decode_kv(kv, acc) when is_binary(kv), do: decode_key(kv, kv, 0, acc)

  defp decode_key(<<h, t::binary>>, _key_rest, _len, acc)
       when h in [?\s, ?\t, ?\r, ?\n, ?\v, ?\f],
       do: skip_until_cc(t, acc)

  defp decode_key(<<?;, t::binary>>, _key_rest, _len, acc), do: decode_kv(t, acc)
  defp decode_key(<<?=, t::binary>>, _key_rest, 0, acc), do: skip_until_cc(t, acc)

  defp decode_key(<<?=, t::binary>>, key_rest, len, acc) do
    key = binary_part(key_rest, 0, len)
    decode_value(t, t, 0, 0, key, acc)
  end

  defp decode_key(<<_, t::binary>>, key_rest, len, acc), do: decode_key(t, key_rest, len + 1, acc)
  defp decode_key(<<>>, _key_rest, _len, acc), do: acc

  defp decode_value(<<?;, t::binary>>, val_rest, len, spaces, key, acc) do
    value = binary_part(val_rest, 0, len - spaces)
    decode_kv(t, [{key, value} | acc])
  end

  defp decode_value(<<?\s, t::binary>>, val_rest, len, spaces, key, acc) do
    decode_value(t, val_rest, len + 1, spaces + 1, key, acc)
  end

  defp decode_value(<<h, t::binary>>, _val_rest, _len, _spaces, _key, acc)
       when h in [?\t, ?\r, ?\n, ?\v, ?\f],
       do: skip_until_cc(t, acc)

  defp decode_value(<<_, t::binary>>, val_rest, len, _spaces, key, acc) do
    decode_value(t, val_rest, len + 1, 0, key, acc)
  end

  defp decode_value(<<>>, val_rest, len, spaces, key, acc) do
    value = binary_part(val_rest, 0, len - spaces)
    [{key, value} | acc]
  end

  defp skip_until_cc(<<?;, t::binary>>, acc), do: decode_kv(t, acc)
  defp skip_until_cc(<<_, t::binary>>, acc), do: skip_until_cc(t, acc)
  defp skip_until_cc(<<>>, acc), do: acc

  @doc """
  Encodes the given cookies as expected in a response header.

  ## Examples

      iex> encode("key1", %{value: "value1"})
      "key1=value1; path=/; HttpOnly"

      iex> encode("key1", %{value: "value1", secure: true, path: "/example", http_only: false})
      "key1=value1; path=/example; secure"
  """
  def encode(key, opts \\ %{}) when is_map(opts) do
    value = Map.get(opts, :value)
    path = Map.get(opts, :path, "/")

    key = to_string(key)
    value = to_string(value)
    path = to_string(path)

    acc = [key, ?=, value, "; path=", path]
    acc = if domain = opts[:domain], do: [acc, "; domain=", domain], else: acc
    acc = if max_age = opts[:max_age], do: [acc | encode_max_age(max_age, opts)], else: acc
    acc = if Map.get(opts, :secure, false), do: [acc | "; secure"], else: acc
    acc = if Map.get(opts, :http_only, true), do: [acc | "; HttpOnly"], else: acc

    acc =
      if same_site = Map.get(opts, :same_site), do: [acc | encode_same_site(same_site)], else: acc

    acc = if extra = opts[:extra], do: [acc, "; ", extra], else: acc

    IO.iodata_to_binary(acc)
  end

  defp encode_max_age(max_age, opts) do
    time = Map.get(opts, :universal_time) || :calendar.universal_time()
    time = add_seconds(time, max_age)
    ["; expires=", rfc2822(time), "; max-age=", Integer.to_string(max_age)]
  end

  defp encode_same_site(value) when is_binary(value), do: ["; SameSite=", value]

  defp pad(n) when n < 10, do: <<?0, ?0 + n>>
  defp pad(n), do: <<?0 + div(n, 10), ?0 + rem(n, 10)>>

  defp rfc2822({{year, month, day} = date, {hour, minute, second}}) do
    # Sat, 17 Apr 2010 14:00:00 GMT
    [
      weekday_name(:calendar.day_of_the_week(date)),
      ?,,
      ?\s,
      pad(day),
      ?\s,
      month_name(month),
      ?\s,
      Integer.to_string(year),
      ?\s,
      pad(hour),
      ?:,
      pad(minute),
      ?:,
      pad(second),
      " GMT"
    ]
  end

  defp weekday_name(1), do: "Mon"
  defp weekday_name(2), do: "Tue"
  defp weekday_name(3), do: "Wed"
  defp weekday_name(4), do: "Thu"
  defp weekday_name(5), do: "Fri"
  defp weekday_name(6), do: "Sat"
  defp weekday_name(7), do: "Sun"

  defp month_name(1), do: "Jan"
  defp month_name(2), do: "Feb"
  defp month_name(3), do: "Mar"
  defp month_name(4), do: "Apr"
  defp month_name(5), do: "May"
  defp month_name(6), do: "Jun"
  defp month_name(7), do: "Jul"
  defp month_name(8), do: "Aug"
  defp month_name(9), do: "Sep"
  defp month_name(10), do: "Oct"
  defp month_name(11), do: "Nov"
  defp month_name(12), do: "Dec"

  defp add_seconds(time, seconds_to_add) do
    time_seconds = :calendar.datetime_to_gregorian_seconds(time)
    :calendar.gregorian_seconds_to_datetime(time_seconds + seconds_to_add)
  end
end
