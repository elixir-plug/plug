defrecord Plug.Connection.Unfetched, [:aspect] do
  @moduledoc """
  A record used as default on unfetched fields
  """

  defimpl Access do
    def access(Plug.Connection.Unfetched[aspect: aspect], key) do
      raise ArgumentError, message:
        "trying to access key #{inspect key} but they were not yet fetched. " <>
        "Please call Plug.Connection.fetch_#{aspect} before accessing it"
    end
  end
end
