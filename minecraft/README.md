# Minecraft Paper telemetry

This guide connects a Minecraft Java Paper server to the Wazuh 4.14.9 baseline.
The production-derived input contract was observed with Paper 26.3 managed by
MineOS.net 1.2.0. Other server implementations and customized log formats are
not assumed to be compatible.

Follow the backup, validation, restart, and rollback gates in
[`INSTALL.md`](../INSTALL.md). Minecraft is an independent optional source.

## Observed bot pattern

The sanitized production window contained:

- 113 pre-login disconnects
- 15 distinct source addresses
- 105 distinct attempted player names
- up to 7 pre-login disconnects in one hour across the server
- up to 3 different attempted names from one source in one hour

The server had online mode, whitelist, and enforce-whitelist enabled. Those
controls rejected the observed attempts; Wazuh adds visibility and correlation,
not authentication or access control.

## Supported Paper log contracts

The pre-login decoder requires this exact shape:

```text
[08:49:45] [Server thread/INFO]: ExamplePlayer1 (/198.51.100.21:61537) lost connection: Disconnected
```

The parentheses and remote endpoint distinguish a pre-login connection from a
normal post-login logout:

```text
[17:07:29] [Server thread/INFO]: ExamplePlayer1 lost connection: Disconnected
```

The second line deliberately does not match the pre-login decoder.

A completed login uses this shape:

```text
[17:03:08] [Server thread/INFO]: ExamplePlayer1[/198.51.100.21:61537] logged in with entity id 76 at ([minecraft:overworld]20.5, 103.0, -3.5)
```

The current contract supports IPv4 addresses and standard Java player names.
It does not claim support for IPv6, offline mode, Bedrock, proxies, localized
messages, or server implementations that rewrite Paper's lines.

## MineOS host path

Do not assume that the path printed inside a container is the host path. Find
the Minecraft bind mount without printing container environment variables:

```bash
docker inspect --format '{{range .Mounts}}{{println .Source "->" .Destination}}{{end}}' MINEOS_API_CONTAINER
```

Replace `MINEOS_API_CONTAINER` with the local MineOS API container name.

Map the server's container path to the corresponding host source and verify the
live log is readable:

```bash
test -r /host/path/to/server/logs/latest.log
stat /host/path/to/server/logs/latest.log
```

The Wazuh agent reads the host file directly. It does not need the Docker socket,
Docker group membership, or a second log-forwarding container.

## Collect the live Paper log

Copy [`wazuh/ossec.conf.snippets/0550-localfiles-minecraft.xml`](../wazuh/ossec.conf.snippets/0550-localfiles-minecraft.xml)
into the Minecraft host agent configuration or its dedicated shared agent group.
Replace the example location with the verified host path to `logs/latest.log`.

Load the `<localfile>` block exactly once. Collecting both the host file and the
same container output would duplicate every event. Archived `.log.gz` files are
for investigation and regression evidence; the live collector follows only
`latest.log`.

## Install the manager files

After creating the manager backup described in `INSTALL.md`, install only the
Minecraft decoder and rules:

```bash
sudo install -o root -g wazuh -m 0640 \
  wazuh/decoders/0600-minecraft-decoders.xml \
  /var/ossec/etc/decoders/0600-minecraft-decoders.xml

sudo install -o root -g wazuh -m 0640 \
  wazuh/rules/0600-minecraft-rules.xml \
  /var/ossec/etc/rules/0600-minecraft-rules.xml
```

## Rules

| Rule | Level | Meaning |
|---|---:|---|
| `100700` | 3 | Paper pre-login connection ended with a remote endpoint |
| `100701` | 5 | Paper rejected a non-whitelisted player |
| `100702` | 8 | Paper could not reach the authentication service |
| `100710` | 10 | Five pre-login disconnects across the server in one hour |
| `100711` | 12 | One source attempted three different player names in one hour |
| `100720` | 3 | Paper player login completed |

Rule `100702` is operational and deliberately excluded from the bot-correlation
group. Rules `100710` and `100711` detect the observed low-rate spray without
raising the severity of every individual disconnect.

## Validate before restart

Run the authoritative manager tests and Minecraft regression scenarios:

```bash
sudo /var/ossec/bin/wazuh-analysisd -t
sudo /var/ossec/bin/wazuh-authd -t
sudo /var/ossec/bin/wazuh-modulesd -t
sudo python3 tools/regression/run_samples.py --samples samples/minecraft
```

Do not restart the manager if any daemon test or regression scenario fails.
After validation passes, restart the manager and verify one known sanitized line
before enabling live collection on the agent.

## Privacy and limitations

Minecraft logs can contain player names, source addresses, chat, coordinates,
world names, plugin output, and command activity. Publish only minimal sanitized
authentication lines. Do not commit complete logs, world seeds, internal paths,
private addresses, chat, or console commands.

The thresholds are based on one low-traffic, ten-player server. Review them for
larger public servers before deployment. These rules provide detection only;
they do not add an active response or modify the whitelist, firewall, MineOS,
Paper, plugins, worlds, or backups.
