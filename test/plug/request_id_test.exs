defmodule Plug.RequestIdTest do

  use ExUnit.Case
  use Plug.Test
  alias Plug.Conn

  defmodule MyPlug do
    use Plug.Builder

    plug Plug.RequestId
    plug :passthrough

    defp passthrough(conn, _) do
      Plug.Conn.send_resp(conn, 200, "Passthrough")
    end
  end

  defmodule CustomHeaderPlug do
    use Plug.Builder

    plug Plug.RequestId, http_header: "custom-request-id"
    plug :passthrough

    defp passthrough(conn, _) do
      Plug.Conn.send_resp(conn, 200, "Passthrough")
    end
  end

  test "generates new request id if none exists" do
    conn = conn(:get, "/") |> MyPlug.call([])
    [res_request_id] = conn |> Conn.get_resp_header("x-request-id")
    meta_request_id = Dict.fetch!(Logger.metadata, :request_id)
    assert generated_request_id?(res_request_id)
    assert res_request_id == meta_request_id
  end

  test "generates new request id if existing one is invalid" do
    request_id = "tooshort"
    conn =
      conn(:get, "/")
      |> put_req_header("x-request-id", request_id)
      |> MyPlug.call([])
    [res_request_id] = conn |> Conn.get_resp_header("x-request-id")
    meta_request_id = Dict.fetch!(Logger.metadata, :request_id)
    assert res_request_id != request_id
    assert generated_request_id?(res_request_id)
    assert res_request_id == meta_request_id
  end

  test "uses existing request id" do
    request_id = "existingidthatislongenough"
    conn =
      conn(:get, "/")
      |> put_req_header("x-request-id", request_id)
      |> MyPlug.call([])
    [res_request_id] = conn |> Conn.get_resp_header("x-request-id")
    meta_request_id = Dict.fetch!(Logger.metadata, :request_id)
    assert res_request_id == request_id
    assert res_request_id == meta_request_id
  end

  test "generates new request id in custom header" do
    conn = conn(:get, "/") |> CustomHeaderPlug.call([])
    [res_request_id] = conn |> Conn.get_resp_header("custom-request-id")
    meta_request_id = Dict.fetch!(Logger.metadata, :request_id)
    assert Regex.match?(~r/^[a-z0-9=]+$/u, res_request_id)
    assert res_request_id == meta_request_id
  end

  test "uses existing request id in custom header" do
    request_id = "existingidthatislongenough"
    conn =
      conn(:get, "/")
      |> put_req_header("custom-request-id", request_id)
      |> CustomHeaderPlug.call([])
    [res_request_id] = conn |> Conn.get_resp_header("custom-request-id")
    meta_request_id = Dict.fetch!(Logger.metadata, :request_id)
    assert res_request_id == request_id
    assert res_request_id == meta_request_id
  end

  defp generated_request_id?(request_id) do
    Regex.match?(~r/^[a-z0-9=]+$/u, request_id)
  end
end
