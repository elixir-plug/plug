defmodule Plug.Conn.UtilsTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  import Plug.Conn.Utils
  alias Plug.Conn.Utils, as: Utils
  doctest Plug.Conn.Utils

  @exception RuntimeError
  @context "test context"
  @valid_utf8 "utm_campaign=summer+sale&foo=bar&utm_medium=email&utm_source=sendgrid.com&utm_term=utm_term&utm_content=utm_content&utm_id=utm_id"
  @invalid_utf8 <<"utm_campaign=summer+sale&foo=bar&utm_medium=email&utm_source=sen", 255>>

  setup_all do
    %{
      exception: @exception,
      context: @context,
      valid_utf8: @valid_utf8,
      invalid_utf8: @invalid_utf8
    }
  end

  describe "validate_utf8! with error_code 500" do
    setup context, do: Map.merge(context, %{error_code: 500})

    test "raises an exception for invalid UTF-8 input", context do
      assert_raise context.exception,
                   "invalid UTF-8 on #{context.context}, got byte 255 in position #{byte_size(@invalid_utf8) - 1}",
                   fn ->
                     Utils.validate_utf8!(
                       context.invalid_utf8,
                       context.exception,
                       context.context,
                       context.error_code
                     )
                   end
    end
  end

  describe "validate_utf8! with error_code 404" do
    setup context, do: Map.merge(context, %{error_code: 404})

    test "returns {:error, message} for invalid UTF-8 w/ error code 404",
         context_map do
      %{context: context} = context_map

      error_tuple =
        {:error,
         "invalid UTF-8 on #{context}, got byte 255 in position #{byte_size(@invalid_utf8) - 1}"}

      assert error_tuple ==
               Utils.validate_utf8!(
                 context_map.invalid_utf8,
                 context_map.exception,
                 context_map.context,
                 context_map.error_code
               )
    end
  end

  describe "validate_utf8! with error_code 401" do
    setup context, do: Map.merge(context, %{error_code: 401})

    test "logs a detailed warning for invalid UTF-8 input in position #{byte_size(@invalid_utf8) - 1}",
         context do
      log =
        capture_log(fn ->
          assert :ok =
                   Utils.validate_utf8!(
                     context.invalid_utf8,
                     context.exception,
                     context.context,
                     context.error_code
                   )
        end)

      expected_log_regex =
        ~r/\d{2}:\d{2}:\d{2}\.\d{3} \[warn\] invalid UTF-8 on test context, got byte 255 in position #{byte_size(@invalid_utf8) - 1}/i

      assert String.match?(log, expected_log_regex)
    end
  end
end
