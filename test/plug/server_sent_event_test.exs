defmodule Plug.ServerSentEventTest do
  use ExUnit.Case, async: true

  alias Plug.ServerSentEvent, as: SSE

  test "to_string with empty SSE" do
    assert SSE.to_string(%SSE{}) == "\n\n"
  end

  test "to_string of SSE with just an ID" do
    assert SSE.to_string(%SSE{id: 123}) == "id:123\n\n"
  end

  test "to_string of SSE with just data as a string" do
    assert SSE.to_string(%SSE{data: "foobar"}) == "data:foobar\n\n"
  end

  test "to_string of SSE with just data as a list" do
    assert SSE.to_string(%SSE{data: ["foobar"]}) == "data:foobar\n\n"
  end

  test "to_string of SSE with multiple lines of data" do
    assert SSE.to_string(%SSE{data: ["foobar", "baz"]}) == "data:foobar\ndata:baz\n\n"
  end

  test "to_string of SSE data strips newlines" do
    assert SSE.to_string(%SSE{data: ["foo\nbar", "baz\n\n"]}) == "data:foobar\ndata:baz\n\n"
    assert SSE.to_string(%SSE{data: "foo\nbar"}) == "data:foobar\n\n"
  end

  test "to_string of SSE with just an event" do
    assert SSE.to_string(%SSE{event: "post_created"}) == "event:post_created\n\n"
  end

  test "to_string of SSE with just a retry period" do
    assert SSE.to_string(%SSE{retry: 5000}) == "retry:5000\n\n"
  end

  test "to_string of SSE with multiple fields" do
    assert SSE.to_string(%SSE{id: 345, data: ["foo", "baz"], event: :created, retry: 5000})
      == "id:345\nevent:created\nretry:5000\ndata:foo\ndata:baz\n\n"
  end
end
