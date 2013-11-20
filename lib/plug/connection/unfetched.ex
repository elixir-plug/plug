defrecord Plug.Connection.Unfetched, [:aspect] do
  @moduledoc """
  A record that shows a particular part of connection was not fetched yet.
  """

  defimpl Access do
    def access(Plug.Connection.Unfetched[aspect: aspect], key) do
      raise ArgumentError, message:
        "trying to access key #{inspect key} but they were not yet fetched. " <>
        "Please call Plug.Connection.fetch_#{aspect} before accessing it"
    end
  end
end
