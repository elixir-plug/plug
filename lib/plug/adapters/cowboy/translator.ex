defmodule Plug.Adapters.Cowboy.Translator do
  def translate(_min_level, :error, :format,
                {'Ranch listener' ++ _, [ref, protocol, pid, reason]}) do
    {:ok,
      ["Ranch Protocol ", inspect(pid), " (", inspect(protocol),
        ") of Listener ", inspect(ref), " terminated\n" |
        Exception.format(:exit, reason, [])]}
  end

  def translate(_min_level, _level, _kind, _data) do
    :none
  end
end
