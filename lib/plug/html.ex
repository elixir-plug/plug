defmodule Plug.HTML do
  @moduledoc """
  Conveniences for generating HTML.
  """

  @doc ~S"""
  Escapes the given HTML to string.

      iex> Plug.HTML.html_escape("foo")
      "foo"

      iex> Plug.HTML.html_escape("<foo>")
      "&lt;foo&gt;"

      iex> Plug.HTML.html_escape("quotes: \" & \'")
      "quotes: &quot; &amp; &#39;"
  """
  @spec html_escape(String.t) :: String.t
  def html_escape(data) when is_binary(data) do
    IO.iodata_to_binary(to_iodata(data, 0, data))
  end

  @doc ~S"""
  Escapes the given HTML to iodata.

      iex> Plug.HTML.html_escape_to_iodata("foo")
      "foo"

      iex> Plug.HTML.html_escape_to_iodata("<foo>")
      ["&lt;", "foo", "&gt;" | ""]

      iex> Plug.HTML.html_escape_to_iodata("quotes: \" & \'")
      ["quotes: ", "&quot;", " ", "&amp;", " ", "&#39;" | ""]

  """
  @spec html_escape_to_iodata(String.t) :: iodata
  def html_escape_to_iodata(data) when is_binary(data) do
    to_iodata(data, 0, data)
  end

  @compile {:inline, escape_char: 1}

  @escapes [
    {?<, "&lt;"},
    {?>, "&gt;"},
    {?&, "&amp;"},
    {?", "&quot;"},
    {?', "&#39;"}
  ]
  @escapable Enum.map(@escapes, &elem(&1, 0))

  defp to_iodata(<<char, rest::binary>>, len, original) when char in @escapable do
    escape_char(rest, len, original, char)
  end

  defp to_iodata(<<_, rest::binary>>, len, original) do
    to_iodata(rest, len + 1, original)
  end

  defp to_iodata(<<>>, _length, original) do
    original
  end

  defp escape_char(<<rest::binary>>, 0, _original, char) do
    [escape_char(char) | to_iodata(rest, 0, rest)]
  end

  defp escape_char(<<rest::binary>>, len, original, char) do
    [binary_part(original, 0, len), escape_char(char) | to_iodata(rest, 0, rest)]
  end

  for {match, insert} <- @escapes do
    defp escape_char(unquote(match)), do: unquote(insert)
  end
end
