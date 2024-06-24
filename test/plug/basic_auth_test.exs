defmodule Plug.BasicAuthTest do
  use ExUnit.Case, async: true
  use Plug.Test

  import Plug.BasicAuth

  describe "basic_auth" do
    test "authenticates valid user and password" do
      conn =
        conn(:get, "/")
        |> put_req_header("authorization", encode_basic_auth("hello", "world"))
        |> basic_auth(username: "hello", password: "world")

      refute conn.status
      refute conn.halted
    end

    test "raises key error when no options are given" do
      assert_raise KeyError, fn ->
        conn(:get, "/")
        |> put_req_header("authorization", encode_basic_auth("hello", "world"))
        |> basic_auth()
      end
    end

    test "refutes invalid user and password" do
      for {user, pass} <- [{"hello", "wrong"}, {"wrong", "hello"}] do
        conn =
          conn(:get, "/")
          |> put_req_header("authorization", encode_basic_auth(user, pass))
          |> basic_auth(username: "hello", password: "world")

        assert conn.halted
        assert conn.status == 401
        assert conn.resp_body == "Unauthorized"
        assert get_resp_header(conn, "www-authenticate") == ["Basic realm=\"Application\""]
      end
    end
  end

  describe "encode_basic_auth" do
    test "encodes the given user and password" do
      assert encode_basic_auth("hello", "world") == "Basic aGVsbG86d29ybGQ="
    end
  end

  describe "parse_basic_auth" do
    test "returns :error with no authentication header" do
      assert conn(:get, "/")
             |> parse_basic_auth() == :error
    end

    test "returns :error with another authentication header" do
      assert conn(:get, "/")
             |> put_req_header("authorization", "Token abcdef")
             |> parse_basic_auth() == :error
    end

    test "returns :error with invalid base64 token" do
      assert conn(:get, "/")
             |> put_req_header("authorization", "Basic abcdef")
             |> parse_basic_auth() == :error
    end

    test "returns :error with only username or password in token" do
      assert conn(:get, "/")
             |> put_req_header("authorization", "Basic #{Base.encode64("hello")}")
             |> parse_basic_auth() == :error
    end

    test "returns username and password" do
      assert conn(:get, "/")
             |> put_req_header("authorization", encode_basic_auth("hello", "world"))
             |> parse_basic_auth() == {"hello", "world"}

      assert conn(:get, "/")
             |> put_req_header("authorization", encode_basic_auth("hello", "long:world"))
             |> parse_basic_auth() == {"hello", "long:world"}
    end
  end

  describe "request_basic_auth" do
    test "sets www-authenticate header with realm information" do
      assert conn(:get, "/")
             |> request_basic_auth()
             |> get_resp_header("www-authenticate") == ["Basic realm=\"Application\""]

      assert conn(:get, "/")
             |> request_basic_auth(realm: ~S|"tricky"|)
             |> get_resp_header("www-authenticate") == ["Basic realm=\"tricky\""]
    end
  end
end
