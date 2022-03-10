use Mix.Config

config :logger, :console, format: "$time $metadata[$level] $message\n"

if Mix.env() == :test do
  config :plug, :statuses, %{
    418 => "Totally not a teapot",
    998 => "Not An RFC Status Code"
  }
end
