defmodule Plug.Adapters.Cowboy2.BadResponseCheck do
  require Logger

  def init(stream_id, req, opts) do
    :cowboy_stream.init(stream_id, req, opts)
  end

  def data(stream_id, is_fin, data, state) do
    :cowboy_stream.data(stream_id, is_fin, data, state)
  end

  def info(stream_id, info, state) do
    :cowboy_stream.info(stream_id, info, state)
  end

  def terminate(_stream_id, reason, _state) do
    {:exit, reason}
  end

  def early_error(_stream_id, reason, _partial_req, resp, _opts) do
    case reason do
      {:connection_error, :limit_reached, _} ->
        Logger.error("""
        Cowboy returned 431 and there are no headers in the connection.

        This may happen if Cowboy is unable to parse the request headers,
        for example, because there are too many headers or the header name
        or value are too large (such as a large cookie).

        You can customize those values when configuring your http/https
        server. The configuration option and default values are shown below:

        protocol_options: [
          max_header_name_length: 64,
          max_header_value_length: 4096,
          max_headers: 100
        ]
        """)

      _ ->
        nil
    end

    resp
  end
end
