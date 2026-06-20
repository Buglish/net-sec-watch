# Phase 2 – Optional Zeek Network-Metadata Sensor

Zeek complements router syslog by observing network traffic and generating
structured connection, DNS, HTTP, TLS, DHCP, and notice logs. It does not
replace firewall logs, and it does not need to decrypt TLS payloads to produce
connection and handshake metadata.

## Start the optional profile

Initialize local configuration:

```bash
make init
```

Set the capture interface in the private `.env`:

```dotenv
ZEEK_INTERFACE=eth1
ZEEK_LOG_VOLUME=zeek-logs
```

The default named volume avoids creating root-owned files in the repository.
To consume logs written by a separate host sensor, set `ZEEK_LOG_VOLUME` to
that absolute directory instead.

Then start Fluent Bit and Zeek:

```bash
make up-zeek
make logs-zeek
```

Zeek writes JSON logs beneath `ZEEK_LOG_ROOT`; Fluent Bit tails those logs and
adds vendor-neutral fields while retaining Zeek's native fields.

## Sensor placement

Zeek sees only packets delivered to its capture interface. Choose one:

- **Managed-switch mirror/SPAN port:** mirror the router uplink and selected
  LAN/VLAN ports to a dedicated Zeek interface.
- **Network TAP:** connect a TAP monitor output to the sensor.
- **Gateway interface:** run Zeek on a Linux gateway carrying the traffic.

Do not assume a normal Wi-Fi or Docker/WSL virtual interface can observe other
devices' traffic. Docker Desktop is useful for fixture testing, but a dedicated
Linux sensor or mirrored physical interface is recommended for live use.

## Privacy and capacity

Zeek records endpoints, hostnames, protocol details, and timing. It does not
store full packet payloads by default, but logs can still contain sensitive
information. Approve scope, retention, access, and redaction before production.

Monitor capture loss, CPU, disk growth, and log volume. High-throughput links
may require a dedicated sensor, multiple workers, and packet-capture tuning.

## Verification

Repository fixtures and normalization are tested with:

```bash
make test-integration
```

For live capture, generate DNS and HTTPS traffic visible to the selected
interface, then look for `zeek.conn`, `zeek.dns`, and `zeek.ssl` events:

```bash
make logs
```
