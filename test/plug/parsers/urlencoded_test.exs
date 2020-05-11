defmodule Plug.Parsers.URLENCODEDTest do
  use ExUnit.Case, async: true

  alias Plug.Parsers.URLENCODED

  test "Parses the request body with non utf8 character and option validate_utf8: true" do
    conn = %Plug.Conn{
      adapter:
        {Plug.Adapters.Test.Conn,
         %{
           req_body: "variable_with_non_utf8_character=%90"
         }}
    }

    assert_raise(
      Plug.Parsers.BadEncodingError,
      "invalid UTF-8 on urlencoded params, got byte 144",
      fn ->
        URLENCODED.parse(
          conn,
          "application",
          "x-www-form-urlencoded",
          [],
          {{Plug.Conn, :read_body, []}, [validate_utf8: true]}
        )
      end
    )
  end

  test "Parses the request body with non utf8 character and option validate_utf8: false" do
    conn = %Plug.Conn{
      adapter:
        {Plug.Adapters.Test.Conn,
         %{
           req_body: "variable_with_non_utf8_character=%90"
         }}
    }

    assert {:ok, %{"variable_with_non_utf8_character" => <<144>>}, _conn} =
             URLENCODED.parse(
               conn,
               "application",
               "x-www-form-urlencoded",
               [],
               {{Plug.Conn, :read_body, []}, [validate_utf8: false]}
             )
  end
end
