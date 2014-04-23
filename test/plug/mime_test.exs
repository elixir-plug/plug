defmodule Plug.MIMETest do
  use ExUnit.Case, async: true

  import Plug.MIME

  doctest Plug.MIME

  test :valid? do
    assert valid?("application/json")
    refute valid?("application/prs.vacation-photos")
  end

  test :extensions do
    assert "json" in extensions("application/json")
    assert extensions("application/vnd.api+json") == []
  end

  test :type do
    assert type("json") == "application/json"
    assert type("foo") == "application/octet-stream"
  end
end
