import Config

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  colors: [enabled: false],
  metadata: [:request_id]

if Mix.env() == :test do
  config :plug, :statuses, %{
    418 => "Totally not a teapot",
    998 => "Not An RFC Status Code"
  }
end
