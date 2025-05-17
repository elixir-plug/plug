defmodule Plug.RequestId do
  @moduledoc """
  A plug for generating a unique request ID for each request.

  The generated request ID will be in the format:

  ```
  GEBMr97eLMHtGWsAAAVj
  ```

  If a request ID already exists in a configured HTTP request header (see options below),
  then this plug will use that value, *assuming it is between 20 and 200 characters*.
  If such header is not present, this plug will generate a new request ID.

  The request ID is added to the `Logger` metadata as `:request_id`, and to the
  response as the configured HTTP response header (see options below). To see the
  request ID in your log output, configure your logger formatter to include the `:request_id`
  metadata. For example:

      config :logger, :default_formatter, metadata: [:request_id]

  We recommend to include this metadata configuration in your production
  configuration file.

  > #### Programmatic access to the request ID {: .tip}
  >
  > To access the request ID programmatically, use the `:assign_as` option (see below)
  > to assign the request ID to a key in `conn.assigns`, and then fetch it from there.

  ## Usage

  To use this plug, just plug it into the desired module:

      plug Plug.RequestId

  ## Options

    * `:http_header` - The name of the HTTP *request* header to check for
      existing request IDs. This is also the HTTP *response* header that will be
      set with the request id. Default value is `"x-request-id"`.

          plug Plug.RequestId, http_header: "custom-request-id"

    * `:assign_as` - The name of the key that will be used to store the
      discovered or generated request id in `conn.assigns`. If not provided,
      the request id will not be stored. *Available since v1.16.0*.

          plug Plug.RequestId, assign_as: :plug_request_id

    * `:logger_metadata_key` - The name of the key that will be used to store the
      discovered or generated request id in `Logger` metadata. If not provided,
      the request ID Logger metadata will be stored as `:request_id`. *Available
      since v1.18.0*.

          plug Plug.RequestId, logger_metadata_key: :my_request_id

  """

  require Logger
  alias Plug.Conn
  @behaviour Plug

  @impl true
  def init(opts) do
    {
      Keyword.get(opts, :http_header, "x-request-id"),
      Keyword.get(opts, :assign_as),
      Keyword.get(opts, :logger_metadata_key, :request_id)
    }
  end

  @impl true
  def call(conn, {header, assign_as, logger_metadata_key}) do
    request_id = get_request_id(conn, header)

    Logger.metadata([{logger_metadata_key, request_id}])
    conn = if assign_as, do: Conn.assign(conn, assign_as, request_id), else: conn

    Conn.put_resp_header(conn, header, request_id)
  end

  defp get_request_id(conn, header) do
    case Conn.get_req_header(conn, header) do
      [] -> generate_request_id()
      [val | _] -> if valid_request_id?(val), do: val, else: generate_request_id()
    end
  end

  defp generate_request_id do
    binary = <<
      System.system_time(:nanosecond)::64,
      :erlang.phash2({node(), self()}, 16_777_216)::24,
      :erlang.unique_integer()::32
    >>

    Base.url_encode64(binary)
  end

  defp valid_request_id?(s), do: byte_size(s) in 20..200
end
