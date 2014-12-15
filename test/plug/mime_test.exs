defmodule Plug.MIMETest do
  use ExUnit.Case, async: true

  import Plug.MIME

  doctest Plug.MIME

  test "valid?/1" do
    assert valid?("application/json")
    refute valid?("application/prs.vacation-photos")
  end

  test "extensions/1" do
    assert "json" in extensions("application/json")
    assert extensions("application/vnd.api+json") == []
  end

  test "type/1" do
    assert type("json") == "application/json"
    assert type("foo") == "application/octet-stream"
  end

  test "path/1" do
    assert path("index.html") == "text/html"
    assert path("inexistent.filetype") == "application/octet-stream"
    assert path("without-extension") == "application/octet-stream"
  end
end
