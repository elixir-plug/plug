defmodule Plug.Telemetry do
  @moduledoc """
  A plug to instrument the pipeline with `:telemetry` events.

  When plugged, the event prefix is a required option:

      plug Plug.Telemetry, event_prefix: [:my, :plug]

  In the example above, two events will be emitted:

    * `[:my, :plug, :start]` - emitted when the plug is invoked.
      The event carries the `system_time` as measurement. The metadata
      is the whole `Plug.Conn` under the `:conn` key and any leftover
      options given to the plug under `:options`.

    * `[:my, :plug, :stop]` - emitted right before the response is sent.
      The event carries a single measurement, `:duration`,  which is the
      monotonic time difference between the stop and start events.
      It has the same metadata as the start event, except the connection
      has been updated.

  Note this plug measures the time between its invocation until a response
  is sent. The `:stop` event is not guaranteed to be emitted in all error
  cases, so this Plug cannot be used as a Telemetry span.

  You can manually emit events including a `:duration` measurement from any
  subsequent step in your plug pipeline by calling `execute_measurement/3`.

  ## Time unit

  The `:duration` measurements are presented in the `:native` time unit.
  You can read more about it in the docs for `System.convert_time_unit/3`.

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
    {event_prefix, opts} = Keyword.pop(opts, :event_prefix)

    unless event_prefix do
      raise ArgumentError, ":event_prefix is required"
    end

    ensure_valid_event_prefix!(event_prefix)

    {event_prefix, opts}
  end

  @impl true
  def call(conn, {event_prefix, opts}) do
    private = %{start_time: System.monotonic_time(), event_prefix: event_prefix, opts: opts}

    conn
    |> Plug.Conn.put_private(:plug_telemetry, private)
    |> Plug.Conn.register_before_send(&execute_measurement/1)
    |> execute(:start, %{system_time: System.system_time()})
  end

  defp ensure_valid_event_prefix!(event_prefix) do
    if is_list(event_prefix) && Enum.all?(event_prefix, &is_atom/1) do
      :ok
    else
      raise ArgumentError,
            "expected :event_prefix to be a list of atoms, got: #{inspect(event_prefix)}"
    end
  end

  defp execute(%Plug.Conn{private: private} = conn, name, measurements, metadata \\ %{}) do
    %{plug_telemetry: %{event_prefix: event_prefix, opts: opts}} = private

    metadata = Map.merge(metadata, %{conn: conn, options: opts})
    :telemetry.execute(event_prefix ++ [name], measurements, metadata)

    conn
  end

  @doc """
  This is the new interface I'd like to have
  """
  @spec execute_measurement(Plug.Conn.t()) :: Plug.Conn.t()
  @spec execute_measurement(Plug.Conn.t(), atom) :: Plug.Conn.t()
  @spec execute_measurement(Plug.Conn.t(), atom, map) :: Plug.Conn.t()
  def execute_measurement(%Plug.Conn{private: private} = conn, name \\ :stop, metadata \\ %{})
      when is_atom(name) and is_map(metadata) do
    %{plug_telemetry: %{start_time: start_time}} = private

    execute(conn, name, %{duration: System.monotonic_time() - start_time}, metadata)
  end
end
