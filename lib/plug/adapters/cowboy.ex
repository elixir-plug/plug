defmodule Plug.Adapters.Cowboy do
  @moduledoc false

  @doc false
  def http(plug, opts, cowboy_options \\ []) do
    unless using_plug_cowboy?(), do: warn_and_raise()
    Plug.Cowboy.http(plug, opts, cowboy_options)
  end

  @doc false
  def https(plug, opts, cowboy_options \\ []) do
    unless using_plug_cowboy?(), do: warn_and_raise()
    Plug.Cowboy.https(plug, opts, cowboy_options)
  end

  @doc false
  def shutdown(ref) do
    unless using_plug_cowboy?(), do: warn_and_raise()
    Plug.Cowboy.shutdown(ref)
  end

  @doc false
  def child_spec(scheme, plug, opts, cowboy_options \\ []) do
    unless using_plug_cowboy?(), do: warn_and_raise()
    Plug.Cowboy.child_spec(scheme, plug, opts, cowboy_options)
  end

  @doc false
  def child_spec(opts) do
    unless using_plug_cowboy?(), do: warn_and_raise()
    Plug.Cowboy.child_spec(opts)
  end

  defp using_plug_cowboy?() do
    Code.ensure_loaded?(Plug.Cowboy)
  end

  defp warn_and_raise() do
    error = """
    please add the following dependency to your mix.exs:

        {:plug_cowboy, "~> 1.0"}

    This dependency is required by Plug.Adapters.Cowboy
    which you may be using directly or indirectly.
    Note you no longer need to depend on :cowboy directly.
    """

    IO.warn(error, [])
    :erlang.raise(:exit, "plug_cowboy dependency missing", [])
  end
end
