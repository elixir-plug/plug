defmodule Plug.RequestId do
  @moduledoc """
  A plug for generating a unique request id for each request.

  The generated request id will be in the format "uq8hs30oafhj5vve8ji5pmp7mtopc08f".

  If a request id already exists as the "x-request-id" HTTP request header,
  then that value will be used assuming it is between 20 and 200 characters.
  If it is not, a new request id will be generated.

  The request id is added to the Logger metadata as `:request_id` and the response as
  the "x-request-id" HTTP header. To see the request id in your log output,
  configure your logger backends to include the `:request_id` metadata:

      config :logger, :console, metadata: [:request_id]

  It is recommended to include this metadata configuration in your production
  configuration file.

  You can also access the `request_id` programmatically by calling
  `Logger.metadata[:request_id]`. Do not access it via the request header, as
  the request header value has not been validated and it may not always be
  present.

  To use this plug, just plug it into the desired module:

      plug Plug.RequestId

  ## Options

    * `:http_header` - The name of the HTTP *request* header to check for
      existing request ids. This is also the HTTP *response* header that will be
      set with the request id. Default value is "x-request-id"

          plug Plug.RequestId, http_header: "custom-request-id"

    * `:assign_as` - The name of the key that will be used to store the
      discovered or generated request id in `conn.assigns`. If not provided,
      the request id will not be stored.

          plug Plug.RequestId, assign_as: :plug_request_id

  """

  require Logger
  alias Plug.Conn
  @behaviour Plug

  @impl true
  def init(opts) do
    {
      Keyword.get(opts, :http_header, "x-request-id"),
      Keyword.get(opts, :assign_as)
    }
  end

  @impl true
  def call(conn, {header, assign_as}) do
    conn
    |> get_request_id(header)
    |> set_request_id(header, assign_as)
  end

  defp get_request_id(conn, header) do
    case Conn.get_req_header(conn, header) do
      [] -> {conn, generate_request_id()}
      [val | _] -> if valid_request_id?(val), do: {conn, val}, else: {conn, generate_request_id()}
    end
  end

  defp set_request_id({conn, request_id}, header, assign_as) do
    Logger.metadata(request_id: request_id)

    conn = if assign_as, do: Conn.assign(conn, assign_as, request_id), else: conn

    Conn.put_resp_header(conn, header, request_id)
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
