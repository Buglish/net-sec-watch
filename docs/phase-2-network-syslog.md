# Phase 2 – Network-Device and Syslog Collection

## Overview

Net Sec Watch accepts syslog from routers, firewalls, switches, and appliances
via UDP (RFC 3164), TCP (RFC 3164), and TLS-protected TCP (RFC 5424).

## Ports

| Protocol | Host port | Container port | Format   | Use                         |
|----------|-----------|----------------|----------|-----------------------------|
| UDP      | 514       | 5514           | RFC 3164 | Consumer routers, switches  |
| TCP      | 514       | 5514           | RFC 3164 | Reliable delivery, plain    |
| TLS/TCP  | 6514      | 6514           | RFC 5424 | Enterprise devices, privacy |

Ports 514/udp and 514/tcp are standard syslog ports. The container uses
non-privileged port 5514 internally; Docker maps the host port.
TLS on 6514 requires separate certificate setup (see below).

## Quick start

```bash
make up    # starts Fluent Bit with UDP and TCP receivers on port 514
make logs  # confirm net.syslog.udp and net.syslog.tcp inputs start
```

Test reception locally:

```bash
# UDP — this matches the protocol normally used by an ASUS RT-AC68U
printf '<134>%s myhost app: test message\n' "$(date '+%b %d %H:%M:%S')" |
  nc -u -w1 127.0.0.1 514

# TCP — omitting -u tests TCP, not the ASUS router's usual UDP transport
printf '<134>%s myhost app: test message\n' "$(date '+%b %d %H:%M:%S')" |
  nc -w1 127.0.0.1 514
```

Confirm the test message appears in collector output:

```bash
make logs   # look for "net.syslog.udp" records with your test string
```

## Record fields

Each syslog record includes:

| Field                        | Source                              |
|------------------------------|-------------------------------------|
| `pri`                        | Parsed from message `<PRI>` prefix  |
| `host`                       | Parsed hostname from message        |
| `ident`                      | Parsed application name             |
| `pid`                        | Parsed process ID (if present)      |
| `message`                    | Parsed log message body             |
| `net.src_ip`                 | Sender IP address                   |
| `net.transport`              | `udp` or `tcp`                      |
| `log.syslog.facility.code`   | Integer facility (PRI / 8)          |
| `log.syslog.facility.name`   | Facility name (e.g. `daemon`)       |
| `log.syslog.severity.code`   | Integer severity (PRI % 8)          |
| `log.syslog.severity.name`   | Severity name (e.g. `info`)         |
| `event.receive_time`         | UTC timestamp when Fluent Bit received the record |
| `event.original`             | Reconstructed raw syslog line       |

## Dead-letter stream

Records that fail RFC 3164 parsing (missing or empty `host` field) are
re-tagged to `net.syslog.deadletter` and gain a `_dead_letter: true` marker.
All outputs match `*` so dead-letter records are visible in collector stdout.
In Phase 4, route this tag to a separate OpenSearch index.

## TLS certificate setup

Generate self-signed certificates once:

```bash
make gen-tls-certs
```

Creates `config/tls/` (git-ignored) containing:

- `ca.crt` — CA certificate; install on sender devices as a trusted root
- `server.crt` — server certificate for Fluent Bit
- `server.key` — server private key (never commit; chmod 600)

Enable the TLS input:

```bash
cp config/fluent-bit.local.conf.example config/fluent-bit.local.conf
# Uncomment the TLS syslog INPUT block in fluent-bit.local.conf
```

In `.env`:

```
FLUENT_BIT_CONFIG_PATH=./config/fluent-bit.local.conf
```

Then restart:

```bash
make down && make up
```

## Configuring an ASUS router (Asuswrt stock firmware)

For an RT-AC68U running stock Asuswrt firmware:

1. Log in at `http://router.asus.com` or `http://192.168.1.1`.
2. Open **System Log → General Log**.
3. In **Remote Log Server**, enter only the computer's LAN IP address, for
   example `192.168.1.209`.
4. Select **Apply**.

Do not enter `192.168.1.209:514/UDP`. Stock Asuswrt validates this field as a
hostname or IP address and reports an FQDN error when a port or protocol is
included. On this firmware, remote logging uses UDP syslog port 514
automatically.

Asuswrt-Merlin firmware exposes more logging controls and supports TCP syslog.
Stock firmware resets local logs on reboot; remote forwarding persists them here.

Sample fixture showing the expected message format:
`examples/logs/network/asus-router-rfc3164.log`

## Finding your LAN IP (Windows / WSL2)

The router must send to the Windows computer's LAN address. Do not configure
the router with the Docker container address (`172.18.x.x`) or the WSL address
(`172.x.x.x`); those addresses are private to the computer and can change.

Open PowerShell or Command Prompt and run:

```powershell
ipconfig
```

Find the active Ethernet or Wi-Fi adapter that has the same network as the
router's default gateway. For example:

```text
Wireless LAN adapter WiFi:
   IPv4 Address . . . . . . . . . . : 192.168.1.209
   Default Gateway . . . . . . . . . : 192.168.1.1
```

In this example, configure the router's remote log destination as:

```text
Server IP: 192.168.1.209
Port:      514
Protocol:  UDP
```

PowerShell can also list likely addresses:

```powershell
Get-NetIPAddress -AddressFamily IPv4 |
  Where-Object { $_.IPAddress -notlike '169.*' -and $_.IPAddress -ne '127.0.0.1' } |
  Select-Object IPAddress, InterfaceAlias
```

### Confirm Docker publishes the syslog port

From the repository in WSL, run:

```bash
docker compose --env-file .env port fluent-bit 5514/udp
```

The expected output includes:

```text
5514/udp -> 0.0.0.0:514
5514/tcp -> 0.0.0.0:514
```

This means Docker accepts traffic on the Windows host's port 514 and forwards
it to the container. `0.0.0.0` means all host network interfaces; it is not an
address to enter into the router.

### Allow UDP 514 through Windows Firewall

Run PowerShell as Administrator:

```powershell
New-NetFirewallRule `
  -DisplayName "Net Sec Watch Syslog UDP" `
  -Direction Inbound `
  -Protocol UDP `
  -LocalPort 514 `
  -Action Allow `
  -Profile Private
```

Restrict the rule to the router address where practical:

```powershell
Set-NetFirewallRule `
  -DisplayName "Net Sec Watch Syslog UDP" `
  -RemoteAddress 192.168.1.1
```

Use the router's actual LAN address if it is not `192.168.1.1`.

### Verify that router events arrive

Start following the collector output:

```bash
make logs
```

Then apply the remote-log settings on the router or generate router activity.
Incoming events should include `"net.transport":"udp"` and a `net.src_ip`
value. If local UDP tests work but router events do not appear, check the
Windows firewall rule, router destination address, and whether the Wi-Fi
network is marked **Private** in Windows.

### RT-AC68U verification evidence

The RT-AC68U UDP syslog completion gate is tracked in
`docs/test-results/phase-2-rt-ac68u-udp-syslog.md`.

The verified scope is system events and selected firewall/drop events exposed by
stock Asuswrt. This does not turn router syslog into complete network-flow
telemetry; use Zeek or Suricata on mirrored, tapped, or gateway traffic for
fuller connection metadata.

## WSL2 port forwarding

On WSL2, Docker runs inside a virtual machine with its own IP (172.x.x.x).
Your router sends syslog to the Windows LAN IP, not to WSL2 directly.

### Option A – WSL2 mirrored networking (recommended, Windows 11 22H2+)

Add to `%USERPROFILE%\.wslconfig` on Windows, then restart WSL2:

```ini
[wsl2]
networkingMode=mirrored
```

```powershell
wsl --shutdown
```

With mirrored networking WSL2 shares the Windows network stack. No port
forwarding is needed; your LAN IP routes directly into WSL2.

### Option B – Windows port proxy (TCP only)

`netsh portproxy` does **not** support UDP. Use this for TCP syslog only.

Run in an **elevated PowerShell** after each WSL2 start (the WSL2 IP changes on restart):

```powershell
$wslIp = (wsl -- hostname -I).Trim().Split()[0]

netsh interface portproxy add v4tov4 `
  listenport=514 listenaddress=0.0.0.0 `
  connectport=514 connectaddress=$wslIp

netsh advfirewall firewall add rule `
  name="Net Sec Watch Syslog TCP" protocol=TCP dir=in localport=514 action=allow

Write-Host "WSL2 IP: $wslIp — configure your router to send to your Windows LAN IP on port 514."
```

To remove the rule when no longer needed:

```powershell
netsh interface portproxy delete v4tov4 listenport=514 listenaddress=0.0.0.0
```

### UDP on WSL2 without mirrored networking

`netsh portproxy` only forwards TCP. For UDP syslog without mirrored
networking, choose one of:

- Enable mirrored networking (Option A above).
- Run a UDP reflector on Windows (e.g., `socat UDP-LISTEN:514,fork UDP:<wsl-ip>:514`).
- Use TCP syslog on the router side and Option B for forwarding.
- Run the collector directly on Windows (Docker Desktop, no WSL2 needed).

## Monitoring UDP receive errors

Fluent Bit exposes per-input record counts at the metrics endpoint:

```bash
curl -s http://localhost:2020/api/v1/metrics | python3 -m json.tool
```

Look for `input.syslog.X.records` counts. A sustained count of zero during
expected traffic indicates packets are not reaching the receiver.

Kernel-level UDP socket statistics (run inside the collector container):

```bash
docker compose --env-file .env exec fluent-bit \
  sh -c 'cat /proc/net/udp 2>/dev/null || echo "not available"'
```

The `drops` column in `/proc/net/udp` shows kernel receive-buffer overflow
drops. Increase the socket receive buffer if drops are non-zero:

```bash
# On the Docker host (not inside the container)
sysctl -w net.core.rmem_max=26214400
sysctl -w net.core.rmem_default=26214400
```

## UDP limitations

UDP syslog provides no delivery acknowledgement or retransmission. Under
high packet rates or host load, the kernel may silently drop packets before
Fluent Bit reads them. Consequences:

- Events are lost without any error visible in Fluent Bit logs.
- The `net_ratelimit` kernel mechanism can suppress repeated messages.
- Filesystem buffering in Fluent Bit protects against *output* interruptions
  but cannot recover events dropped before the input socket.

Use TCP syslog for applications where log loss is unacceptable.

## Redundant receivers

Running two collector instances on separate hosts provides resilience against
single-collector failure. Configure your device to send syslog to both:

- Devices with dual-target syslog (e.g. Asuswrt-Merlin, most enterprise firmware):
  configure two separate remote log destinations.
- Devices with a single target: use a UDP/TCP reflector on the primary host to
  duplicate traffic to the secondary.

The integration tests cover single-collector TCP recovery (filesystem buffer
survives restart). True dual-receiver testing requires a multi-host environment.

The repository also includes a local resilience test with two independent
receiver containers:

```bash
make test-failover
```

It verifies:

- UDP dual-target delivery reaches both receivers.
- A TCP sender uses the primary while it is healthy.
- The TCP sender selects the secondary when the primary is stopped.
- The primary can recover while the secondary remains available.

UDP has no connection or acknowledgement, so a sender cannot detect that an
individual UDP receiver is unavailable. Devices that support multiple syslog
targets should send UDP to both. TCP/TLS devices can retry a secondary target
after connection failure.

### RT-AC68U resilience limitation

Stock Asuswrt on the RT-AC68U provides one remote-log-server field and sends
UDP to that single destination. It cannot perform receiver health checks or
sender-side failover. For resilient router collection, configure the router
with one stable address backed by one of these designs:

- A small always-on syslog relay that duplicates events to two collectors.
- A highly available virtual IP shared by two receiver hosts.
- A network load balancer that supports UDP health checks and preserves the
  required source metadata.

The local Docker container is currently a single receiver. The automated
failover test validates the intended two-receiver behavior, but production
resilience requires two separate hosts or failure domains.
