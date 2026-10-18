# Minecraft Paper samples

These scenarios preserve the punctuation and event shapes observed in Paper
logs while replacing player names, source addresses, ports, coordinates, and
other deployment-specific values.

Coverage includes:

- a single pre-login disconnect (`100700`)
- a whitelist rejection (`100701`)
- an authentication-service outage (`100702`)
- five distributed pre-login attempts in one hour (`100710`)
- three different player names from one source in one hour (`100711`)
- a completed player login (`100720`)
- a normal post-login disconnect that must not trigger pre-login rules

All addresses use RFC 5737 documentation ranges. The samples contain no real
player names, source addresses, hostnames, world seeds, or server paths.
