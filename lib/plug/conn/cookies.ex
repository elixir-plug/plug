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
  def decode(cookie) do
    cookie
    |> :binary.split(";", [:global])
    |> Enum.reduce(%{}, fn kv, acc ->
      case decode_kv(kv) do
        {k, v} -> Map.put(acc, k, v)
        false -> acc
      end
    end)
  end

  defp decode_kv(""), do: false
  defp decode_kv(kv) do
    kv
    |> String.trim()
    |> decode_key("")
  end

  defp decode_key("", _key), do: false
  defp decode_key(<<?=, _::binary>>, ""), do: false
  defp decode_key(<<?=, t::binary>>, key) do
    value = case t do
      "" -> ""
      _ -> String.trim(t)
    end
    {key, value}
  end
  defp decode_key(<<h, _::binary>>, _key) when h in [?\s, ?\t, ?\r, ?\n, ?\v, ?\f], do: false
  defp decode_key(<<h, t::binary>>, key), do: decode_key(t, <<key::binary, h>>)

  @doc """
  Encodes the given cookies as expected in a response header.
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
