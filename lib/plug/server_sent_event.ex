defmodule Plug.ServerSentEvent do
  @moduledoc """
  A module to generate messages according to the W3C Server-Sent Events
  spec (http://www.w3.org/TR/eventsource/).
  """
  @type id    :: integer | String.t | nil
  @type data  :: String.t | list(String.t) | []
  @type event :: String.t | nil
  @type retry :: integer | nil

  defstruct id:    nil :: id,
            data:  []  :: data,
            event: nil :: event,
            retry: nil :: retry

  alias __MODULE__, as: SSE

  @doc """
  Transforms a ServerSentEvent to a String so it can be sent to the client.

  It expects a Plug.ServerSentEvent struct as it's argument, returns a String
  which can be passed as the body to the connection adapter.
  """
  @spec to_string(t) :: String.t
  def to_string(%SSE{} = chunk) do
    add_id_to_string([], chunk)
    |> add_event_to_string(chunk)
    |> add_retry_to_string(chunk)
    |> add_data_to_string(chunk)
    |> finalize
  end

  defp add_id_to_string(acc, %SSE{id: id}) do
    add_field_to_string(acc, "id", id)
  end

  defp add_event_to_string(acc, %SSE{event: event}) do
    add_field_to_string(acc, "event", event)
  end

  defp add_retry_to_string(acc, %SSE{retry: retry}) when is_integer(retry) or retry == nil do
    add_field_to_string(acc, "retry", retry)
  end

  defp add_data_to_string(acc, %SSE{data: data}) when is_binary(data) do
    add_field_to_string(acc, "data", data)
  end
  defp add_data_to_string(acc, %SSE{data: data}) do
    Enum.map(data, &build_line("data", &1))
    |> Enum.reverse
    |> Enum.concat(acc)
  end

  defp add_field_to_string(acc, _, nil), do: acc
  defp add_field_to_string(acc, field_name, field_value) do
    [build_line(field_name, field_value)] ++ acc
  end

  defp build_line(field_name, field_value) do
    if is_binary(field_value) do
      value = String.replace(field_value, "\n", "")
      line(field_name, value)
    else
      line(field_name, field_value)
    end
  end

  defp line(field_name, field_value) do
    "#{field_name}:#{field_value}\n"
  end

  defp finalize([]), do: "\n\n"
  defp finalize(acc) do
    Enum.reverse(acc, ["\n"])
    |> Enum.join
  end
end
