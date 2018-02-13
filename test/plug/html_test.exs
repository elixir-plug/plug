defmodule Plug.HTMlTest do
  use ExUnit.Case, async: true
  doctest Plug.HTML

  import Plug.HTML, only: [html_escape: 1]

  test "escapes HTML" do
    assert html_escape("<script>") == "&lt;script&gt;"
    assert html_escape("html&company") == "html&amp;company"
    assert html_escape("\"quoted\"") == "&quot;quoted&quot;"
    assert html_escape("html's test") == "html&#39;s test"
  end

  test "escapes HTML to iodata" do
    assert iodata_escape("<script>") == "&lt;script&gt;"
    assert iodata_escape("html&company") == "html&amp;company"
    assert iodata_escape("\"quoted\"") == "&quot;quoted&quot;"
    assert iodata_escape("html's test") == "html&#39;s test"
  end

  defp iodata_escape(data) do
    data |> Plug.HTML.html_escape_to_iodata() |> IO.iodata_to_binary()
  end
end
