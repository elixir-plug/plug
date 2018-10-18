defmodule Plug.Cowboy do
  def http(_, _, _) do
    {:ok, :http}
  end

  def https(_, _, _) do
    {:ok, :https}
  end

  def shutdown(_) do
    {:ok, :shutdown}
  end

  def child_spec(_, _, _, _) do
    {:ok, :child_spec}
  end

  def child_spec(_) do
    {:ok, :child_spec}
  end
end
