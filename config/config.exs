use Mix.Config

if Mix.env() == :test do
  config :plug, :statuses, %{
    418 => "Totally not a teapot",
    998 => "Not An RFC Status Code"
  }
end
