defmodule Plug.Adapters.Cowboy.Translator do

  def translate(min_level, :error, :format,
                {'Ranch listener' ++ _, [ref, protocol, pid, reason]}) do
    {:ok, translate_ranch(min_level, ref, protocol, pid, reason)}
  end

  def translate(_min_level, _level, _kind, _data) do
    :none
  end

  defp translate_ranch(min_level, ref, :cowboy_protocol, pid,
                       {reason, {mod, :call, [%Plug.Conn{} = conn, opts]}}) do
    [inspect(mod), ?\s, inspect(pid), " of Listener ", inspect(ref),
      " terminated\n",
      plug_info(min_level, conn, opts) |
      Exception.format(:exit, reason, [])]
  end

  defp translate_ranch(_min_level, ref, protocol, pid, reason) do
    ["Ranch Protocol ", inspect(pid), " (", inspect(protocol),
        ") of Listener ", inspect(ref), " terminated\n" |
        Exception.format(:exit, reason, [])]
  end

  defp plug_info(:debug, conn, opts) do
    ["Plug Options: ", inspect(opts), ?\n |
      conn_info(:debug, conn)]
  end

  defp plug_info(min_level, conn, _opts) do
    conn_info(min_level, conn)
  end

  defp conn_info(min_level, %Plug.Conn{host: host, method: method,
                                       path_info: path_info,
                                       query_string: query_string} = conn) do
    ["Host: ", host, ?\n,
      transport_debug(min_level, conn),
      "Method: ", method, ?\n,
      "Path Info: ", inspect(path_info), ?\n,
      "Query String: ", inspect(query_string), ?\n |
      conn_debug(min_level, conn)]
  end

  defp transport_debug(:debug, %Plug.Conn{scheme: scheme, port: port}) do
    ["Scheme: ", Atom.to_string(scheme), ?\n,
      "Port: ", Integer.to_string(port), ?\n]
  end

  defp transport_debug(_min_level, _conn) do
    []
  end

  defp conn_debug(:debug, %Plug.Conn{req_headers: headers}) do
    prefix = "    "
    Enum.reduce(headers, "Headers:\n",
                fn({header, value}, acc) ->
                    [acc, prefix, header, ": ", value, ?\n]
                end)
  end

  defp conn_debug(_min_level, _conn) do
    []
  end
end
