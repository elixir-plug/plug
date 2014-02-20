defmodule Plug.Runtime do
  @moduledoc """
  A wrapper to set an “x-runtime” response header, indicating the response
  time of the request, in seconds

  ## Options

  *  `:name` - a custom suffix used in header name.
               This allow the use of multiple Runtime
               wrappers in an app.

  ## Examples

      Plug.Runtime.wrap(conn, Plug.Runtime.init([]), fun)
  """
  import Plug.Connection

  @behaviour Plug.Wrapper

  def init(opts) do
    header_name = "x-runtime"
    if opts[:name], do: header_name = header_name <> "-#{opts[:name]}"
    Keyword.put(opts, :name, header_name)
  end

  def wrap(conn, opts, fun) do
    start_time = :os.timestamp
    conn = fun.(conn)
    request_time = :timer.now_diff(:os.timestamp, start_time) / 1000000

    header_name = opts[:name]
    unless conn.resp_headers[header_name] do
      formated_time = to_string(:io_lib.format("~f", [request_time]))
      conn = put_resp_header(conn, header_name, formated_time)
    end
    conn
  end
end
