defmodule Plug.Conn.StatusTest do
  use ExUnit.Case

  alias Plug.Conn.Status

  test "code/1 when given a numeric status code, returns the same numeric status code" do
    assert Status.code(200) == 200
    assert Status.code(203) == 203
    assert Status.code(404) == 404
  end

  test "code for built-in statuses the numeric code" do
    assert Status.code(:ok) == 200
    assert Status.code(:non_authoritative_information) == 203
    assert Status.code(:not_found) == 404
  end

  test "code for custom status return the numeric code" do
    assert Status.code(:not_an_rfc_status_code) == 998
  end

  test "code with both a built_in and custom code return the numeric code" do
    assert Status.code(:im_a_teapot) == 418
    assert Status.code(:totally_not_a_teapot) == 418
  end

  test "reason_atom returns the atom for built-in statuses" do
    assert Status.reason_atom(200) == :ok
    assert Status.reason_atom(203) == :non_authoritative_information
    assert Status.reason_atom(404) == :not_found
  end

  test "reason_atom returns the atom for custom statuses" do
    assert Status.reason_atom(998) == :not_an_rfc_status_code
  end

  test "reason_atom with both a built_in and custom status always returns the custom atom" do
    assert Status.reason_atom(418) == :totally_not_a_teapot
  end

  test "reason_atom with an unknown code raises an error" do
    assert_raise(ArgumentError, "unknown status code 999", fn ->
      Status.reason_atom(999)
    end)
  end

  test "reason_phrase returns the phrase for built_in statuses" do
    assert Status.reason_phrase(200) == "OK"
    assert Status.reason_phrase(203) == "Non-Authoritative Information"
    assert Status.reason_phrase(404) == "Not Found"
  end

  test "reason_phrase for custom status return the phrase" do
    assert Status.reason_phrase(998) == "Not An RFC Status Code"
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
