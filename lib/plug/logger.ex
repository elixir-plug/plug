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

    start = current_time()

    Conn.register_before_send(conn, fn conn ->
      Logger.log level, fn ->
        stop = current_time()
        diff = time_diff(start, stop)

        [connection_type(conn), ?\s, Integer.to_string(conn.status),
         " in ", formatted_diff(diff)]
      end
      conn
    end)
  end

  # TODO: remove this once Plug supports only Elixir 1.2.
  if function_exported?(:erlang, :monotonic_time, 0) do
    defp current_time, do: :erlang.monotonic_time
    defp time_diff(start, stop), do: (stop - start) |> :erlang.convert_time_unit(:native, :micro_seconds)
  else
    defp current_time, do: :os.timestamp()
    defp time_diff(start, stop), do: :timer.now_diff(stop, start)
  end

  defp formatted_diff(diff) when diff > 1000, do: [diff |> div(1000) |> Integer.to_string, "ms"]
  defp formatted_diff(diff), do: [diff |> Integer.to_string, "µs"]

  defp connection_type(%{state: :chunked}), do: "Chunked"
  defp connection_type(_), do: "Sent"
end
