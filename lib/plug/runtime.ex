defmodule Plug.Runtime do
  import Plug.Connection

  @behaviour Plug.Wrapper

  def init(opts) do
    header_name = "x-runtime"
    if opts[:name], do: header_name = header_name <> "-#{opts[:name]}"
    Keyword.put(opts, :name, header_name)
  end

  def wrap(conn, opts, fun) do
    start_time = :erlang.now
    conn = fun.(conn)
    request_time = :timer.now_diff(:erlang.now, start_time) / 1000000

    header_name = opts[:name]
    unless conn.resp_headers[header_name] do
      formated_time = to_string(:io_lib.format("~f", [request_time]))
      conn = put_resp_header(conn, header_name, formated_time)
    end
    conn
  end
end
