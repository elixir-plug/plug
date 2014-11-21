defmodule Plug.Adapters.Translator do
  @moduledoc """
  A translator module shared by adapters that ship with Plug.

  We host all translations into a single module which is added
  to Logger when the :plug application starts.
  """

  ## Entry point

  def translate(min_level, :error, :format,
                {'Ranch listener' ++ _, [ref, protocol, pid, reason]}) do
    {:ok, translate_ranch(min_level, ref, protocol, pid, reason)}
  end

  def translate(_min_level, _level, _kind, _data) do
    :none
  end

  ## Ranch/Cowboy

  defp translate_ranch(min_level, _ref, :cowboy_protocol, pid,
                       {reason, {mod, :call, [%Plug.Conn{} = conn, _opts]}}) do
    [inspect(pid), " running ", inspect(mod), " terminated\n",
      conn_info(min_level, conn) |
      Exception.format(:exit, reason, [])]
  end

  defp translate_ranch(_min_level, ref, protocol, pid, reason) do
    ["Ranch Protocol ", inspect(pid), " (", inspect(protocol),
      ") of Listener ", inspect(ref), " terminated\n" |
      Exception.format(:exit, reason, [])]
  end

  ## Helpers

  defp conn_info(_min_level, conn) do
    [server_info(conn), request_info(conn)]
  end

  defp server_info(%Plug.Conn{host: host, port: port, scheme: scheme}) do
    ["Server: ", host, ":", Integer.to_string(port), ?\s, ?(, Atom.to_string(scheme), ?), ?\n]
  end

  defp request_info(%Plug.Conn{method: method, path_info: path_info,
                               query_string: query_string}) do
    ["Request: ", method, ?\s, path_to_iodata(path_info, query_string), ?\n]
  end

  defp path_to_iodata(path, ""), do: path_to_iodata(path)
  defp path_to_iodata(path, qs), do: [path_to_iodata(path), ??, qs]

  defp path_to_iodata([]),   do: [?/]
  defp path_to_iodata(path), do: Enum.reduce(path, [], fn(i, acc) -> [acc, ?/, i] end)
end
