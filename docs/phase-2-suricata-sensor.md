# Phase 2 – Optional Suricata IDS and Flow Sensor

Suricata complements router syslog and Zeek with signature-based IDS alerts,
network flows, protocol metadata, and anomaly records. Net Sec Watch consumes
Suricata's standard EVE JSON output from `eve.json`.

The provided profile is passive IDS mode. It observes traffic and generates
evidence; it is not configured as an inline IPS and does not block packets.

## Start the optional profile

Set the capture interface in the private `.env`:

```dotenv
SURICATA_IMAGE=jasonish/suricata:8.0.5
SURICATA_INTERFACE=eth1
SURICATA_LOG_VOLUME=suricata-logs
```

Start Fluent Bit and Suricata:

```bash
make update-suricata-rules
make up-suricata
make logs-suricata
```

The default named volumes retain EVE logs and Suricata rule state without
creating root-owned files in the repository.

## Sensor placement

Suricata must receive copies of the packets to inspect:

- Connect a dedicated sensor interface to a managed-switch SPAN/mirror port.
- Use the monitor output of a network TAP.
- Run the sensor on a Linux gateway interface carrying the traffic.

Docker Desktop and ordinary WSL virtual interfaces generally cannot see all
LAN traffic. Use them for configuration and fixture testing; use a dedicated
Linux sensor or correctly mirrored interface for meaningful live coverage.

## Rules and operation

Suricata requires maintained IDS rules for useful alerts. The update target
uses the image's open-source `suricata-update` tool and stores downloaded rules
in the private `suricata-rules` volume. Review and approve every configured rule
source and its license before production use. Treat rules as versioned security
content: record their source and version, test updates, monitor false positives,
and provide rollback. Flow and protocol records do not depend on every packet
matching a signature.

Do not enable inline IPS mode until rule quality, bypass behavior, performance,
and recovery have been tested separately. The current project remains passive.

## Privacy, performance, and packet loss

EVE logs can contain endpoints, DNS names, URLs, TLS names, certificate data,
and alert evidence. Approve collection scope, retention, access, and redaction.
Monitor capture drops, engine statistics, CPU, memory, disk use, and log volume.

## Verification

Sanitized EVE fixtures and normalization are covered by:

```bash
make test-integration
```

For live capture, generate traffic visible to the selected interface and look
for `suricata.flow`, `suricata.dns`, `suricata.http`, `suricata.tls`, and
`suricata.alert` records:

```bash
make logs
```
