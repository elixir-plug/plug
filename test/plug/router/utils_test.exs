defmodule Plug.Router.UtilsTest do
  use ExUnit.Case, async: true

  require Plug.Router.Utils, as: R
  doctest Plug.Router.Utils

  @opts [context: Plug.Router.Utils]

  defp build_path_match(route) do
    R.build_path_match(route, Plug.Router.Utils)
  end

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
    assert quote(@opts, do: {[], ["foo"]}) == build_path_match("/foo")
    assert quote(@opts, do: {[], ["foo"]}) == build_path_match("foo")
  end

  test "build match with identifier" do
    assert quote(@opts, do: {[:id], ["foo", id]}) == build_path_match("/foo/:id")
    assert quote(@opts, do: {[:username], ["foo", username]}) == build_path_match("foo/:username")
  end

  test "build match with multiple identifiers" do
    assert quote(@opts, do: {[:id, :name, :category], ["foo", id, name, category]}) ==
             build_path_match("/foo/:id/:name/:category")

    assert quote(@opts,
             do: {[:username, :post_id, :comment_id], ["foo", username, post_id, comment_id]}
           ) ==
             build_path_match("foo/:username/:post_id/:comment_id")

    assert quote(@opts, do: {[:username, :post1, :post2], ["foo", username, post1, post2]}) ==
             build_path_match("foo/:username/:post1/:post2")
  end

  test "build match with literal plus identifier" do
    assert quote(@opts, do: {[:id], ["foo", "bar-" <> id]}) == build_path_match("/foo/bar-:id")

    assert quote(@opts, do: {[:username], ["foo", "bar" <> username]}) ==
             build_path_match("foo/bar:username")
  end

  test "build match only with glob" do
    assert quote(@opts, do: {[:bar], bar}) == build_path_match("*bar")
    assert quote(@opts, do: {[:glob], glob}) == build_path_match("/*glob")
  end

  test "build match with glob" do
    assert quote(@opts, do: {[:bar], ["foo" | bar]}) == build_path_match("/foo/*bar")
    assert quote(@opts, do: {[:glob], ["foo" | glob]}) == build_path_match("foo/*glob")
  end

  test "build invalid match with empty matches" do
    assert_raise Plug.Router.InvalidSpecError,
                 "invalid dynamic path. The characters : and * must be immediately followed by lowercase letters or underscore, got: :",
                 fn -> build_path_match("/foo/:") end
  end

  test "build invalid match with non word character" do
    assert_raise Plug.Router.InvalidSpecError,
                 "invalid dynamic path. Only letters, numbers, and underscore are allowed after : in \"/foo/:bar.baz\"",
                 fn -> build_path_match("/foo/:bar.baz") end
  end

  test "build invalid match with segments after glob" do
    assert_raise Plug.Router.InvalidSpecError,
                 "globs (*var) must always be in the last path, got glob in: \"*bar\"",
                 fn -> build_path_match("/foo/*bar/baz") end
  end

  test "build invalid match with multiple identifiers" do
    assert_raise Plug.Router.InvalidSpecError,
                 "only one dynamic entry (:var or *glob) per path segment is allowed, got: \":bar.:baz\"",
                 fn -> build_path_match("/foo/:bar.:baz") end
  end

  test "build invalid match with suffix glob" do
    assert_raise Plug.Router.InvalidSpecError,
                 "globs (*var) cannot be followed by suffixes, got: \"*bar-baz\"",
                 fn -> build_path_match("/foo/*bar-baz") end
  end
end
