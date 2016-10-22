use Mix.Config

if Mix.env == :test do
  config :plug, :statuses, %{
    418 => "Totally not a teapot",
    451 => "Unavailable For Legal Reasons"
  }
end
