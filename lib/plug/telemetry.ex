defmodule Plug.Telemetry do
  @moduledoc """
  A plug to instrument the pipeline with `:telemetry` events.

  Currently the following events are emitted (event names assume that `:event_prefix` option is set
  to `[:my, :plug]` - more on that in the paragraph below):
    * `[:my, :plug, :call, :start]` - emitted right after this plug is invoked. There are no
      measurements in this event, and the only metadata is the whole `Plug.Conn` under the `:conn`
      key
    * `[:my, :plug, :call, :stop]` - emitted right before the request is sent back. The event carries
      a single measurement, `:duration`, which is the monotonic time difference between the stop
      and start events. The duration is presented in the `:native` time unit (see docs for
      `System.convert_time_unit/3` for more information). The same as for the start event, the only
      metadata is the `Plug.Conn` struct under the `:conn` key.

  The names of the events are based on the provided `event_prefix`: for the start event, the name is
  `event_prefix ++ [:call, :start]`, and for the stop event: `event_prefix ++ [:call, :stop]`.
  The event prefix is required, so that event consumers can differentiate between events emitted by
  multiple instances of this plug.

  Note that this plug measures only the time between its invocation and the rest of the plug pipeline -
  this can be used to exclude some plugs from measurement.

  ## Example

      defmodule InstrumentedPlug do
        use Plug.Router

        plug :match

        plug Plug.Telemetry, event_prefix: [:my, :plug]
        plug Plug.Parsers, parsers: [:urlencoded, :multipart]

        plug :dispatch

        get "/" do
          send_resp(conn, 200, "Hello, world!")
        end
      end

  In this example, the stop event's `duration` includes the time it takes to parse the request,
  dispatch it to the correct handler, and execute the handler. The events are not emitted for requests
  not matching any handlers, since the plug is placed after the match plug.
  """

  @behaviour Plug

  @impl true
  def init(opts) do
    event_prefix = ensure_event_prefix!(opts)
    ensure_valid_event_prefix!(event_prefix)
    start_event = event_prefix ++ [:call, :start]
    stop_event = event_prefix ++ [:call, :stop]
    {start_event, stop_event}
  end

  @impl true
  def call(conn, {start_event, stop_event}) do
    start_time = System.monotonic_time()
    :telemetry.execute(start_event, %{}, %{conn: conn})

    Plug.Conn.register_before_send(conn, fn conn ->
      duration = System.monotonic_time() - start_time

      :telemetry.execute(stop_event, %{duration: duration}, %{
        conn: conn
      })

      conn
    end)
  end

  defp ensure_event_prefix!(opts) do
    case Keyword.fetch(opts, :event_prefix) do
      {:ok, event_prefix} ->
        event_prefix

      _ ->
        raise ArgumentError, ":event_prefix is required"
    end
  end

  defp ensure_valid_event_prefix!(event_prefix) do
    if is_list(event_prefix) && Enum.all?(event_prefix, &is_atom/1) do
      :ok
    else
      raise ArgumentError,
            "expected :event_prefix to be a list of atoms, got: #{inspect(event_prefix)}"
    end
  end
end
