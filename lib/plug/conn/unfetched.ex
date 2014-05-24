defmodule Plug.Conn.Unfetched do
  @moduledoc """
  A struct used as default on unfetched fields.
  """
  defstruct [:aspect]

  defimpl Access do
    def get(%Plug.Conn.Unfetched{aspect: aspect}, key) do
      raise ArgumentError, message:
        "trying to access key #{inspect key} but they were not yet fetched. " <>
        "Please call Plug.Conn.fetch_#{aspect} before accessing it"
    end

    def access(unfetched, key) do
      get(unfetched, key)
    end
  end
end
