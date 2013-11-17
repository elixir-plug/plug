defmodule Plug.Connection.CookiesTest do
  use ExUnit.Case, async: true

  import Plug.Connection.Cookies
  doctest Plug.Connection.Cookies

  test "decode cookies" do
    assert decode("key1=value1, key2=value2") ==
           [{ "key1", "value1" }, { "key2", "value2" }]

    assert decode("key1=value1; key2=value2") ==
           [{ "key1", "value1" }, { "key2", "value2" }]

    assert decode("$key1=value1, key2=value2; $key3=value3") ==
           [{ "key2", "value2" }]

    assert decode("key space=value, key=value space") ==
           [{ "key", "value space" }]

    assert decode("  key1=value1 , key2=value2  ") ==
           [{ "key1", "value1" }, { "key2", "value2" }]

    assert decode("") == []
    assert decode("key, =, value") == []
    assert decode("key=") == [{ "key", "" }]
    assert decode("key1=;;key2=") == [{ "key1", "" }, { "key2", "" }]
  end
end
