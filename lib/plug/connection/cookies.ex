defmodule Plug.Connection.Cookies do
  @moduledoc """
  Conveniences for encoding and decoding cookies.
  """

  @doc """
  Decodes the given cookies.

  If a cookie is invalid, it is automatically
  discarded from the result.

  ## Examples

      iex> decode("key1=value1, key2=value2")
      [{ "key1", "value1" }, { "key2", "value2" }]

  """
  def decode(cookie) do
    decode_each(:binary.split(cookie, [";", ","], [:global]))
  end

  defp decode_each([]),
    do: []
  defp decode_each([h|t]) do
    case decode_kv(h) do
      { _, _ } = kv -> [kv|decode_each(t)]
      false -> decode_each(t)
    end
  end

  defp decode_kv(""),
    do: false
  defp decode_kv(<< ?$, _ :: binary >>),
    do: false
  defp decode_kv(<< h, t :: binary >>) when h in [?\s, ?\t],
    do: decode_kv(t)
  defp decode_kv(kv),
    do: decode_key(kv, "")

  defp decode_key("", _key),
    do: false
  defp decode_key(<< ?=, _ :: binary >>, ""),
    do: false
  defp decode_key(<< ?=, t :: binary >>, key),
    do: decode_value(t, "", key, "")
  defp decode_key(<< h, _ :: binary >>, _key) when h in [?\s, ?\t, ?\r, ?\n, ?\v, ?\f],
    do: false
  defp decode_key(<< h, t :: binary >>, key),
    do: decode_key(t, << key :: binary, h >>)

  defp decode_value("", _spaces, key, value),
    do: { key, value }
  defp decode_value(<< ?\s, t :: binary >>, spaces, key, value),
    do: decode_value(t, << spaces :: binary, ?\s >>, key, value)
  defp decode_value(<< h, _ :: binary >>, _spaces, _key, _value) when h in [?\t, ?\r, ?\n, ?\v, ?\f],
    do: false
  defp decode_value(<< h, t :: binary >>, spaces, key, value),
    do: decode_value(t, "", key, << value :: binary, spaces :: binary , h >>)
end
