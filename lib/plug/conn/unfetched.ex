defmodule Plug.Conn.Unfetched do
  @moduledoc """
  A struct used as default on unfetched fields.
  """

  defstruct [:aspect]
  @type t :: %__MODULE__{aspect: atom()}

  defimpl Access do
    def get(unfetched, key) do
      raise_no_access(unfetched, key)
    end

    def get_and_update(unfetched, key, _value) do
      raise_no_access(unfetched, key)
    end

    defp raise_no_access(%Plug.Conn.Unfetched{aspect: aspect}, key) do
      raise ArgumentError, message:
        "trying to access key #{inspect key} but they were not yet fetched. " <>
        "Please call Plug.Conn.fetch_#{aspect} before accessing it"
    end
  end
end
