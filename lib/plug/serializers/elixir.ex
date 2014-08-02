defmodule Plug.Serializers.ELIXIR do
  @moduledoc false

  @doc """
  Encode the given Elixir term into a binary.
  """
  def encode(value) do
    :erlang.term_to_binary(value)
  end

  @doc """
  Decode the given binary into an Elixir term.
  """
  def decode(value) do
    :erlang.binary_to_term(value)
  end
end
