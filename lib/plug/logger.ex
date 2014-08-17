defmodule Plug.Logger do
  @moduledoc """
  A plug for logging basic request information. 
  
  It expects no options on initialization.

  To configure just add Logger to your own application and we will utilize it's configuration.

  To include logging of request id's include `:request_id` in your Logger `:metadata` field. 

  If you plan on sending your own request ids they must follow the following format:
  1. Be greater than 20 characters
  2. Be less than 200 characters
  3. Consist of ASCII letters, digits, or the characters +, /, =, and -

  If we receive an invalid request id we will generate a new one.
  """

  require Logger
  alias Plug.Conn
  @behaviour Plug

  def init(opts), do: opts

  def call(conn, _config) do
    request_id = get_request_id(conn)    
    Logger.metadata(request_id: request_id)

    path = path_to_iodata(conn.path_info)
    Logger.info [conn.method, ?\s, path]

    before_time = :os.timestamp()
    Conn.register_before_send(conn, fn (conn) -> 
      after_time = :os.timestamp()
      diff = :timer.now_diff(after_time, before_time)

      resp_time = formatted_diff(diff)
      type = connection_type(conn)
      Logger.info [type, ?\s, Integer.to_string(conn.status), ?\s, "in", ?\s, resp_time]

      Conn.put_resp_header(conn, "x-request-id", request_id)
    end)
  end

  defp generate_request_id, do: :crypto.rand_bytes(15) |> Base.encode64

  defp formatted_diff(diff) do
    if diff > 1000 do
      [Integer.to_string(div(diff, 100)), "ms"]
    else
      [Integer.to_string(diff), "µs"]
    end
  end

  defp connection_type(%{state: :chunked}), do: "Chunked"
  defp connection_type(_), do: "Sent"

  defp path_to_iodata(path), do: Enum.reduce(path, [], fn(i, acc) -> [acc, ?/, i] end)

  defp valid_request_id?(s) do
    Regex.match?(~r/[-A-Za-z0-9+\/=]+/, s) && byte_size(s) in 20..200
  end

  defp get_request_id(conn) do
    request_id = case Conn.get_req_header(conn, "x-request-id") do
      [] -> generate_request_id()
      [val | _] -> val
    end
  
    unless valid_request_id?(request_id) do
      request_id = generate_request_id()
    end

    request_id
  end
end

