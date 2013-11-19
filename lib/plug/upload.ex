defrecord Plug.Upload.File, [:path, :content_type, :filename] do
  @moduledoc """
  Stores information for an uploaded file.
  """
end
