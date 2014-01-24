defmodule Plug.Router.UtilsTest do
  use ExUnit.Case, async: true

  require Plug.Router.Utils, as: R
  doctest Plug.Router.Utils

  @opts [hygiene: [vars: false], context: Plug.Router.Utils]

  test "split on root" do
    assert R.split("/") == []
    assert R.split("") == []
  end

  test "split single segment" do
    assert R.split("/foo") == ["foo"]
    assert R.split("foo") == ["foo"]
  end

  test "split with more than one segment" do
    assert R.split("/foo/bar") == ["foo", "bar"]
    assert R.split("foo/bar") == ["foo", "bar"]
  end

  test "split removes trailing slash" do
    assert R.split("/foo/bar/") == ["foo", "bar"]
    assert R.split("foo/bar/") == ["foo", "bar"]
  end

  test "build match with literal" do
    assert quote(@opts, do: { [], ["foo"] }) == R.build_match("/foo")
    assert quote(@opts, do: { [], ["foo"] }) == R.build_match("foo")
  end

  test "build match with identifier" do
    assert quote(@opts, do: { [:id], ["foo", id] }) == R.build_match("/foo/:id")
    assert quote(@opts, do: { [:username], ["foo", username] }) == R.build_match("foo/:username")
  end

  test "build match with literal plus identifier" do
    assert quote(@opts, do: { [:id], ["foo", "bar-" <> id] }) == R.build_match("/foo/bar-:id")
    assert quote(@opts, do: { [:username], ["foo", "bar" <> username] }) == R.build_match("foo/bar:username")
  end

  test "build match only with glob" do
    assert quote(@opts, do: { [:bar], bar }) == R.build_match("*bar")
    assert quote(@opts, do: { [:glob], glob }) == R.build_match("/*glob")

    assert quote(@opts, do: { [:bar], ["id-" <> _ | _] = bar }) == R.build_match("id-*bar")
    assert quote(@opts, do: { [:glob], ["id-" <> _ | _] = glob }) == R.build_match("/id-*glob")
  end

  test "build match with glob" do
    assert quote(@opts, do: { [:bar], ["foo" | bar] }) == R.build_match("/foo/*bar")
    assert quote(@opts, do: { [:glob], ["foo" | glob] }) == R.build_match("foo/*glob")
  end

  test "build match with literal plus glob" do
    assert quote(@opts, do: { [:bar], ["foo" | ["id-" <> _ | _] = bar] }) == R.build_match("/foo/id-*bar")
    assert quote(@opts, do: { [:glob], ["foo" | ["id-" <> _ | _] = glob] }) == R.build_match("foo/id-*glob")
  end

  test "build invalid match with empty matches" do
    assert_raise Plug.Router.InvalidSpecError,
                 ": must be followed by lowercase letters in routes",
                 fn -> R.build_match("/foo/:") end
  end

  test "build invalid match with segments after glob" do
    assert_raise Plug.Router.InvalidSpecError,
                 "cannot have a *glob followed by other segments",
                 fn -> R.build_match("/foo/*bar/baz") end
  end
end
