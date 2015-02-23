defmodule Plug.Conn.Unfetched do
  @moduledoc """
  A struct used as default on unfetched fields.

  The `:aspect` key of the struct specifies what field is still unfetched.

  ## Examples

      unfetched = %Plug.Conn.Unfetched{aspect: :cookies}

  """

  defstruct [:aspect]
  @type t :: %__MODULE__{aspect: atom()}
end
