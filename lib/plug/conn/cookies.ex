defmodule Plug.Conn.Cookies do
  @moduledoc """
  Conveniences for encoding and decoding cookies.
  """

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
  defp decode_kv(kv, acc) when is_binary(kv), do: decode_key(kv, "", acc)

  defp decode_key(<<h, t::binary>>, _key, acc) when h in [?\s, ?\t, ?\r, ?\n, ?\v, ?\f],
    do: skip_until_cc(t, acc)

  defp decode_key(<<?;, t::binary>>, _key, acc), do: decode_kv(t, acc)
  defp decode_key(<<?=, t::binary>>, "", acc), do: skip_until_cc(t, acc)
  defp decode_key(<<?=, t::binary>>, key, acc), do: decode_value(t, "", 0, key, acc)
  defp decode_key(<<h, t::binary>>, key, acc), do: decode_key(t, <<key::binary, h>>, acc)
  defp decode_key(<<>>, _key, acc), do: acc

  defp decode_value(<<?;, t::binary>>, value, spaces, key, acc),
    do: decode_kv(t, [{key, trim_spaces(value, spaces)} | acc])

  defp decode_value(<<?\s, t::binary>>, value, spaces, key, acc),
    do: decode_value(t, <<value::binary, ?\s>>, spaces + 1, key, acc)

  defp decode_value(<<h, t::binary>>, _value, _spaces, _key, acc)
       when h in [?\t, ?\r, ?\n, ?\v, ?\f],
       do: skip_until_cc(t, acc)

  defp decode_value(<<h, t::binary>>, value, _spaces, key, acc),
    do: decode_value(t, <<value::binary, h>>, 0, key, acc)

  defp decode_value(<<>>, value, spaces, key, acc),
    do: [{key, trim_spaces(value, spaces)} | acc]

  defp skip_until_cc(<<?;, t::binary>>, acc), do: decode_kv(t, acc)
  defp skip_until_cc(<<_, t::binary>>, acc), do: skip_until_cc(t, acc)
  defp skip_until_cc(<<>>, acc), do: acc

  defp trim_spaces(value, 0), do: value
  defp trim_spaces(value, spaces), do: binary_part(value, 0, byte_size(value) - spaces)

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

    IO.iodata_to_binary([
      "#{key}=#{value}; path=#{path}",
      emit_if(opts[:domain], &["; domain=", &1]),
      emit_if(opts[:max_age], &encode_max_age(&1, opts)),
      emit_if(Map.get(opts, :secure, false), "; secure"),
      emit_if(Map.get(opts, :http_only, true), "; HttpOnly"),
      emit_if(Map.get(opts, :same_site, nil), &encode_same_site/1),
      emit_if(opts[:extra], &["; ", &1])
    ])
  end

  defp encode_max_age(max_age, opts) do
    time = Map.get(opts, :universal_time) || :calendar.universal_time()
    time = add_seconds(time, max_age)
    ["; expires=", rfc2822(time), "; max-age=", Integer.to_string(max_age)]
  end

  defp encode_same_site(value) when is_binary(value), do: "; SameSite=#{value}"

  defp emit_if(value, fun_or_string) do
    cond do
      !value ->
        []

      is_function(fun_or_string) ->
        fun_or_string.(value)

      is_binary(fun_or_string) ->
        fun_or_string
    end
  end

  defp pad(number) when number in 0..9, do: <<?0, ?0 + number>>
  defp pad(number), do: Integer.to_string(number)

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
