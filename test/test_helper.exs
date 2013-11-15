ExUnit.start

# For cowboy testing
:application.start(:hackney)
:application.start(:crypto)
:application.start(:ranch)
:application.start(:cowlib)
:application.start(:cowboy)
