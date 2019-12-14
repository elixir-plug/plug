defmodule Plug.BodyReader do
  @callback init(Plug.Conn.t(), opts :: Keyword.t()) :: {:ok, Plug.Conn.t()} | {:error, term}
  @callback close(Plug.Conn.t(), opts :: Keyword.t()) :: {:ok, Plug.Conn.t()} | {:error, term}
  @callback read_body(Plug.Conn.t(), opts :: Keyword.t()) ::
              {:ok, binary, Plug.Conn.t()} | {:more, binary, Plug.Conn.t()} | {:error, term}
end
