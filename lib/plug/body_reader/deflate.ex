defmodule Plug.BodyReader.Deflate do
  @behaviour Plug.BodyReader

  @spec init(Plug.Conn.t(), Keyword.t()) :: {:ok, Plug.Conn.t()} | {:error, term}
  def init(%Plug.Conn{} = conn, _opts) do
    zlib_stream =
      case content_encoding(conn) do
        encoding when encoding in [:deflate, :gzip] ->
          zlib_stream = :zlib.open()
          :ok = :zlib.inflateInit(zlib_stream, window_bits_for_encoding(encoding))
          zlib_stream

        :none ->
          nil
      end

    private =
      conn.private
      |> Map.put(__MODULE__, zlib_stream)

    {:ok, %Plug.Conn{conn | private: private}}
  end

  @spec close(Plug.Conn.t(), Keyword.t()) :: {:ok, Plug.Conn.t()} | {:error, term}
  def close(%Plug.Conn{private: %{__MODULE__ => zlib_stream}} = conn, _opts) do
    if !is_nil(zlib_stream) do
      :ok = :zlib.inflateEnd(zlib_stream)
      :ok = :zlib.close(zlib_stream)
    end

    {:ok, %Plug.Conn{conn | private: Map.delete(conn.private, __MODULE__)}}
  end

  @spec read_body(Plug.Conn.t(), Keyword.t()) ::
          {:ok, binary, Plug.Conn.t()} | {:more, binary, Plug.Conn.t()} | {:error, term}
  def read_body(%Plug.Conn{private: %{__MODULE__ => nil}} = conn, opts) do
    Plug.Conn.read_body(conn, opts)
  end

  def read_body(%Plug.Conn{private: %{__MODULE__ => zlib_stream}} = conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {read_status, body, conn} when read_status in [:ok, :more] ->
        case :zlib.safeInflate(zlib_stream, body) do
          {status, data} when status in [:continue, :finished] ->
            {read_status, IO.iodata_to_binary(data), conn}
        end

      other ->
        other
    end
  end

  defp content_encoding(conn) do
    case Plug.Conn.get_req_header(conn, "content-encoding") do
      ["gzip"] -> :gzip
      ["deflate"] -> :deflate
      [encoding] -> raise Plug.Parsers.ContentEncodingNotSupportedError, encoding: encoding
      _ -> :none
    end
  end

  defp window_bits_for_encoding(:deflate), do: 15
  defp window_bits_for_encoding(:gzip), do: 47
end
