defmodule Plug.Conn.StatusTest do
  use ExUnit.Case

  alias Plug.Conn.Status

  test "code for built-in statuses the numeric code" do
    assert Status.code(:ok) == 200
    assert Status.code(:non_authoritative_information) == 203
    assert Status.code(:not_found) == 404
  end

  test "code for custom status return the numeric code" do
    assert Status.code(:unavailable_for_legal_reasons) == 451
  end

  test "code with both a built_in and custom code return the numeric code" do
    assert Status.code(:im_a_teapot) == 418
    assert Status.code(:totally_not_a_teapot) == 418
  end

  test "reason_phrase returns the phrase for built_in statuses" do
    assert Status.reason_phrase(200) == "OK"
    assert Status.reason_phrase(203) == "Non-Authoritative Information"
    assert Status.reason_phrase(404) == "Not Found"
  end

  test "reason_phrase for custom status return the phrase" do
    assert Status.reason_phrase(451) == "Unavailable For Legal Reasons"
  end

  test "reason_phrase with both a built_in and custom status always returns the custom phrase" do
    assert Status.reason_phrase(418) == "Totally not a teapot"
  end

  test "reason_phrase with an unknown code raises an error" do
    assert_raise(ArgumentError, ~r/unknown status code 999\n\nCustom codes/, fn ->
      Status.reason_phrase(999)
    end)
  end
end
