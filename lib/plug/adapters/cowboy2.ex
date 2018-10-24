defmodule Plug.Adapters.Cowboy2 do
  @moduledoc """
  This module is deprecated. To use Cowboy 2 With Plug please
  include `plug_cowboy` version 2.0 or above in your `mix.exs`
  file. It is recommended that you use the `Plug.Cowboy` module
  directly instead of #{inspect(__MODULE__)}
  """

  @doc false
  def http(plug, opts, cowboy_options \\ []) do
    unless using_plug_cowboy?(), do: warn_and_raise()
    plug_cowboy_deprecation_warning()
    Plug.Cowboy.http(plug, opts, cowboy_options)
  end

  @doc false
  def https(plug, opts, cowboy_options \\ []) do
    unless using_plug_cowboy?(), do: warn_and_raise()
    plug_cowboy_deprecation_warning()
    Plug.Cowboy.https(plug, opts, cowboy_options)
  end

  @doc false
  def shutdown(ref) do
    unless using_plug_cowboy?(), do: warn_and_raise()
    plug_cowboy_deprecation_warning()
    Plug.Cowboy.shutdown(ref)
  end

  @doc false
  def child_spec(opts) do
    unless using_plug_cowboy?(), do: warn_and_raise()
    plug_cowboy_deprecation_warning()
    Plug.Cowboy.child_spec(opts)
  end

  defp using_plug_cowboy?() do
    Code.ensure_loaded?(Plug.Cowboy)
  end

  defp warn_and_raise() do
    error = """
    please add the following dependency to your mix.exs:

        {:plug_cowboy, "~> 2.0"}

    This dependency is required by Plug.Adapters.Cowboy2
    which you may be using directly or indirectly.
    Note you no longer need to depend on :cowboy directly.
    """

    IO.warn(error, [])
    :erlang.raise(:exit, "plug_cowboy dependency missing", [])
  end

  defp plug_cowboy_deprecation_warning() do
    IO.warn("Plug.Adapters.Cowboy2 is deprecated, please use Plug.Cowboy instead")
  end
end
