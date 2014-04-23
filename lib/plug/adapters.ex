# In this file we check if at least one of the adapters are implemented.
# Since right now we only support cowboy, the check is straight-forward.
unless Code.ensure_loaded?(:cowboy_req) do
  raise "cannot compile Plug because the :cowboy application is not available"
end
