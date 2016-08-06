defmodule Plug.Conn.QueryTest do
  use ExUnit.Case, async: true

  import Plug.Conn.Query, only: [decode: 1, encode: 1, encode: 2]
  doctest Plug.Conn.Query

  test "decode queries" do
    params = decode "foo=bar&baz=bat"
    assert params["foo"] == "bar"
    assert params["baz"] == "bat"

    params = decode "users[name]=hello&users[age]=17"
    assert params["users"]["name"] == "hello"
    assert params["users"]["age"]  == "17"

    params = decode("my+weird+field=q1%212%22%27w%245%267%2Fz8%29%3F")
    assert params["my weird field"] == "q1!2\"'w$5&7/z8)?"

    assert decode("=")[""] == ""
    assert decode("key=")["key"] == ""
    assert decode("=value")[""] == "value"

    assert decode("foo[]")["foo"]  == []
    assert decode("foo[]=")["foo"] == [""]
    assert decode("foo[]=bar&foo[]=baz")["foo"] == ["bar", "baz"]
    assert decode("foo[]=bar&foo[]=baz")["foo"] == ["bar", "baz"]

    params = decode("foo[]=bar&foo[]=baz&bat[]=1&bat[]=2")
    assert params["foo"] == ["bar", "baz"]
    assert params["bat"] == ["1", "2"]

    assert decode("x[y][z]=1")["x"]["y"]["z"] == "1"
    assert decode("x[y][z][]=1")["x"]["y"]["z"] == ["1"]
    assert decode("x[y][z]=1&x[y][z]=2")["x"]["y"]["z"] == "2"
    assert decode("x[y][z][]=1&x[y][z][]=2")["x"]["y"]["z"] == ["1", "2"]

    assert (decode("x[y][][z]=1")["x"]["y"] |> Enum.at(0))["z"] == "1"
    assert (decode("x[y][][z][]=1")["x"]["y"] |> Enum.at(0))["z"] |> Enum.at(0) == "1"
  end

  test "last always wins on bad queries" do
    assert decode("x[]=1&x[y]=1")["x"]["y"] == "1"
    assert decode("x[y][][w]=2&x[y]=1")["x"]["y"] == "1"
    assert decode("x=1&x[y]=1")["x"]["y"] == "1"
  end

  test "decode_pair simple queries" do
    params = decode_pair [{"foo", "bar"}, {"baz", "bat"}]
    assert params["foo"] == "bar"
    assert params["baz"] == "bat"
  end

  test "decode_pair one-level nested query" do
    params = decode_pair [{"users[name]", "hello"}]
    assert params["users"]["name"] == "hello"

    params = decode_pair [{"users[name]", "hello"}, {"users[age]", "17"}]
    assert params["users"]["name"] == "hello"
    assert params["users"]["age"]  == "17"
  end

  test "decode_pair query no override" do
    params = decode_pair [{"foo", "bar"}, {"foo", "baz"}]
    assert params["foo"] == "baz"

    params = decode_pair [{"users[name]", "bar"}, {"users[name]", "baz"}]
    assert params["users"]["name"] == "baz"
  end

  test "decode_pair many-levels nested query" do
    params = decode_pair [{"users[name]", "hello"}]
    assert params["users"]["name"] == "hello"

    params = decode_pair [{"users[name]", "hello"}, {"users[age]", "17"}, {"users[address][street]", "Mourato"}]
    assert params["users"]["name"]              == "hello"
    assert params["users"]["age"]               == "17"
    assert params["users"]["address"]["street"] == "Mourato"
  end

  test "decode_pair list query" do
    params = decode_pair [{"foo[]", "bar"}, {"foo[]", "baz"}]
    assert params["foo"] == ["bar", "baz"]
  end

  defp decode_pair(pairs) do
    Enum.reduce Enum.reverse(pairs), %{}, &Plug.Conn.Query.decode_pair(&1, &2)
  end

  test "encode" do
    assert encode(%{foo: "bar", baz: "bat"}) == "baz=bat&foo=bar"

    assert encode(%{foo: nil}) == "foo="
    assert encode(%{foo: "bå®"}) == "foo=b%C3%A5%C2%AE"
    assert encode(%{foo: 1337})  == "foo=1337"
    assert encode(%{foo: ["bar", "baz"]}) == "foo[]=bar&foo[]=baz"

    assert encode(%{users: %{name: "hello", age: 17}}) == "users[age]=17&users[name]=hello"
    assert encode(%{users: [name: "hello", age: 17]}) == "users[name]=hello&users[age]=17"
    assert encode(%{users: [name: "hello", age: 17, name: "goodbye"]}) == "users[name]=hello&users[age]=17"

    assert encode(%{"my weird field": "q1!2\"'w$5&7/z8)?"}) == "my+weird+field=q1%212%22%27w%245%267%2Fz8%29%3F"
    assert encode(%{foo: %{"my weird field": "q1!2\"'w$5&7/z8)?"}}) == "foo[my+weird+field]=q1%212%22%27w%245%267%2Fz8%29%3F"

    assert encode(%{}) == ""
    assert encode([]) == ""

    assert encode(%{foo: [""]}) == "foo[]="

    assert encode(%{foo: ["bar", "baz"], bat: [1, 2]}) == "bat[]=1&bat[]=2&foo[]=bar&foo[]=baz"

    assert encode(%{x: %{y: %{z: 1}}}) == "x[y][z]=1"
    assert encode(%{x: %{y: %{z: [1]}}}) == "x[y][z][]=1"
    assert encode(%{x: %{y: %{z: [1, 2]}}}) == "x[y][z][]=1&x[y][z][]=2"
    assert encode(%{x: %{y: [%{z: 1}]}}) == "x[y][][z]=1"
    assert encode(%{x: %{y: [%{z: [1]}]}}) == "x[y][][z][]=1"
  end

  test "encode with custom encoder" do
    encoder = &(&1 |> to_string |> String.duplicate(2))

    assert encode(%{foo: "bar", baz: "bat"}, encoder) ==
           "baz=batbat&foo=barbar"

    assert encode(%{foo: ["bar", "baz"]}, encoder) ==
           "foo[]=barbar&foo[]=bazbaz"

    assert encode(%{foo: URI.parse("/bar")}, encoder) ==
           "foo=%2Fbar%2Fbar"
  end

  test "encode ignores empty maps or lists" do
    assert encode(%{filter: %{}, foo: "bar", baz: "bat"}) == "baz=bat&foo=bar"
    assert encode(%{filter: [], foo: "bar", baz: "bat"}) == "baz=bat&foo=bar"
  end

  test "encode raises when there's a map with 0 or >1 elems in a list" do
    message = ~r/cannot encode maps inside lists/

    assert_raise ArgumentError, message, fn ->
      encode(%{foo: [%{a: 1, b: 2}]})
    end

    assert_raise ArgumentError, message, fn ->
      encode(%{foo: [%{valid: :map}, %{}]})
    end
  end

  test "raise plug exception on bad www-form" do
    assert_raise Plug.Conn.InvalidQueryError, fn ->
      decode("_utf8=%R2%9P%93")
    end
  end
end
