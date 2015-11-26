defmodule Plug.Logger do
  @moduledoc """
  A plug for logging basic request information in the format:

      GET /index.html
      Sent 200 in 572ms

  To use it, just plug it into the desired module.

      plug Plug.Logger, log: :debug

  ## Options

    * `:log` - The log level at which this plug should log its request info.
      Default is `:info`.
  """

  require Logger
  alias Plug.Conn
  @behaviour Plug

  def init(opts) do
    Keyword.get(opts, :log, :info)
  end

  def call(conn, level) do
    Logger.log level, fn ->
      [conn.method, ?\s, conn.request_path]
    end

    before_time = :os.timestamp()

    Conn.register_before_send(conn, fn conn ->
      Logger.log level, fn ->
        after_time = :os.timestamp()
        diff = :timer.now_diff(after_time, before_time)
        [connection_type(conn), ?\s, Integer.to_string(conn.status),
         " in ", formatted_diff(diff)]
      end
      conn
    end)
  end

  defp formatted_diff(diff) when diff > 1000, do: [diff |> div(1000) |> Integer.to_string, "ms"]
  defp formatted_diff(diff), do: [diff |> Integer.to_string, "µs"]

  defp connection_type(%{state: :chunked}), do: "Chunked"
  defp connection_type(_), do: "Sent"
end
