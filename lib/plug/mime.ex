defmodule Plug.MIME do
  @moduledoc """
  Maps MIME types to file extensions and vice versa.
  """

  @compile :no_native
  @default_type "application/octet-stream"

  @external_resource "lib/plug/mime.types"
  stream = File.stream!("lib/plug/mime.types")

  mapping = Enum.flat_map(stream, fn (line) ->
    if String.match?(line, ~r/^[#\n]/) do
      []
    else
      [type|exts] = String.split(String.strip(line))
      [{type, exts}]
    end
  end)

  @doc """
  Returns whether a MIME type is registered.

      iex> Plug.MIME.valid?("text/plain")
      true
  """

  @spec valid?(String.t) :: boolean
  def valid?(type) do
    is_list entry(type)
  end

  @doc """
  Returns the extensions associated with a MIME type.

      iex> Plug.MIME.extensions("text/html")
      ["html", "htm"]
  """

  @spec extensions(String.t) :: [String.t]
  def extensions(type) do
    entry(type) || []
  end

  @doc """
  Returns the MIME type associated with a file extension.

      iex> Plug.MIME.type("txt")
      "text/plain"
  """

  @spec type(String.t) :: String.t

  for { type, exts } <- mapping, ext <- exts do
    def type(unquote(ext)), do: unquote(type)
  end

  def type(_ext), do: @default_type

  @doc """
  Guesses the MIME type based on the path's extension.

      iex> Plug.MIME.path("index.html")
      "text/html"
  """

  @spec path(Path.r) :: String.t
  def path(path) do
    case Path.extname(path) do
      "." <> ext -> type(ext)
      _ -> @default_type
    end
  end

  # entry/1

  for { type, exts } <- mapping do
    defp entry(unquote(type)), do: unquote(exts)
  end

  defp entry(_type), do: nil
end