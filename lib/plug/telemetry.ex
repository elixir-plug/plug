defmodule Plug.Telemetry do
  @moduledoc """
  A plug to instrument the pipeline with `:telemetry` events.

  When plugged, the event prefix is a required option:

      plug Plug.Telemetry, event_prefix: [:my, :plug]

  In the example above, two events will be emitted:

    * `[:my, :plug, :start]` - emitted when the plug is invoked.
      The event carries a single measurement, `:time`, which is the
      system time in native units at the moment the event is emitted.
      The only metadata is the whole `Plug.Conn` under the `:conn` key.

    * `[:my, :plug, :stop]` - emitted right before the request is sent.
      The event carries a single measurement, `:duration`,  which is the
      monotonic time difference between the stop and start events.
      The same as for the start event, the only metadata is the `Plug.Conn`
      struct under the `:conn` key.

  After the Plug is added, please be sure to add
  [:telemetry](https://github.com/beam-telemetry/telemetry) as
  project dependency.

  Note that this plug measures only the time between its invocation and
  the rest of the plug pipeline - this can be used to exclude some plugs
  from measurement.

  ## Time unit

  Both `:time` and `:duration` measurements are presented in the `:native`
  time unit. You can read more about it in the docs for `System.convert_time_unit/3`.

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

  In this example, the stop event's `duration` includes the time
  it takes to parse the request, dispatch it to the correct handler,
  and execute the handler. The events are not emitted for requests
  not matching any handlers, since the plug is placed after the match plug.
  """

  @behaviour Plug

  @impl true
  def init(opts) do
    event_prefix = opts[:event_prefix] || raise ArgumentError, ":event_prefix is required"
    ensure_valid_event_prefix!(event_prefix)
    start_event = event_prefix ++ [:start]
    stop_event = event_prefix ++ [:stop]
    {start_event, stop_event}
  end

  @impl true
  def call(conn, {start_event, stop_event}) do
    start_time = System.monotonic_time()
    :telemetry.execute(start_event, %{time: System.system_time()}, %{conn: conn})

    Plug.Conn.register_before_send(conn, fn conn ->
      duration = System.monotonic_time() - start_time
      :telemetry.execute(stop_event, %{duration: duration}, %{conn: conn})
      conn
    end)
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
