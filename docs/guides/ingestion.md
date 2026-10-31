# Connect your network

Net Sec Watch doesn't go out and fetch logs. You point each source at it: a
router sends syslog to it, a server forwards its logs, or a sensor watches
copied traffic. This guide covers each way to connect a source, how to check
the data arrives, and what to do when it doesn't.

## Choose how to connect

You can use any mix of these. Start with your router or firewall, add
servers, then add a traffic sensor if you want to see every connection.

| Method | What you get | What you need | Section |
| --- | --- | --- | --- |
| Router or firewall syslog | Blocked and allowed connections, admin logins, device events | Admin access to the device | [1](#1-router-or-firewall-syslog) |
| Linux servers | Logins, `sudo`, SSH failures, service errors | Root on each server | [2](#2-linux-servers) |
| Logs on the Docker host | The host's own system logs and Docker container logs | Docker Engine on Linux | [3](#3-logs-on-the-docker-host) |
| Windows computers | Windows Event Log (logons, service and system events) | A small forwarding agent on each computer | [4](#4-windows-computers) |
| Application log files | Your own applications' text or JSON logs | Access to the log folder | [5](#5-application-log-files) |
| Traffic sensor (Zeek, Suricata) | Every connection, DNS, TLS names, IDS alerts | A switch mirror port, TAP, or Linux gateway, and a Linux machine | [6](#6-traffic-sensor-zeek-and-suricata) |

Router syslog only shows what the router chooses to log, usually blocked
traffic and its own events. It is not a full record of network traffic. For
that, add a [traffic sensor](#6-traffic-sensor-zeek-and-suricata).

## Before you start

1. **Start the stack.** Run `make setup` and open Dashboards at
   `http://127.0.0.1:5601`. See [getting started](getting-started.md).

2. **Find the Docker host's LAN IP.** Devices send logs to this address.

   ```bash
   hostname -I        # Linux: the first 192.168.x.x or 10.x.x.x address
   ```

   On Windows, run `ipconfig` in PowerShell and use the IPv4 address of the
   adapter whose default gateway is your router. Don't use a `172.x.x.x`
   address: those belong to Docker or WSL and other devices can't reach them.
   This guide uses `192.168.1.209` as the example.

3. **Open the syslog port.** The collector listens on port 514 for UDP and TCP
   (`SYSLOG_UDP_PORT` and `SYSLOG_TCP_PORT` in `.env`). Allow it through the
   host firewall:

   ```bash
   sudo ufw allow from 192.168.1.0/24 to any port 514        # Ubuntu/Debian with ufw
   sudo firewall-cmd --permanent --add-port=514/udp --add-port=514/tcp \
     && sudo firewall-cmd --reload                            # Fedora/RHEL
   ```

   **Windows with WSL2:** UDP from other devices doesn't reach WSL2 by
   default. Follow [WSL2 port forwarding](../network-device-syslog-collection.md#wsl2-port-forwarding)
   and [Windows Firewall](../network-device-syslog-collection.md#allow-udp-514-through-windows-firewall)
   first.

4. **Send a test message from another computer** on the same network:

   ```bash
   logger --rfc3164 -n 192.168.1.209 -P 514 -d "NetSecWatchTest001"
   ```

   In Dashboards, open **Discover**, select the `net-sec-watch-network` data
   view, set the time to **Last 15 minutes**, and search
   `NetSecWatchTest001`. If it appears, the network path works and you can
   connect real devices. If it doesn't, see
   [troubleshooting](#troubleshooting).

## 1. Router or firewall syslog

Most routers, firewalls, and managed switches can send their logs to a remote
syslog server. Whatever the device, use these settings:

| Setting | Value |
| --- | --- |
| Server or host | The Docker host's LAN IP, for example `192.168.1.209` |
| Port | `514` |
| Protocol | UDP (TCP if the device offers it, so fewer messages are lost) |
| Format | BSD or RFC 3164. RFC 5424 isn't accepted on port 514 |
| What to send | Firewall events and system events. Avoid debug level |

Most firewalls log a rule only when logging is turned on for that rule.
Turn it on for your block rules at least, and for allow rules if you want to
see accepted connections too.

Menu names change between firmware versions. If a path below doesn't match
your device, search its documentation for "remote syslog".

### ASUS (stock firmware and Asuswrt-Merlin)

1. Open the router admin page, for example `http://192.168.1.1`.
2. Go to **System Log → General Log**.
3. In **Remote Log Server**, enter only the IP, for example `192.168.1.209`.
   Don't add `:514`. Stock firmware rejects it and always uses UDP 514.
4. Select **Apply**.
5. To log dropped connections, go to **Firewall → General** and set
   **Logged packets type** to **Dropped** (or **Both**).

Asuswrt-Merlin also offers TCP and a custom port under the same page. More
detail, including the RT-AC68U test results, is in
[network-device syslog collection](../network-device-syslog-collection.md#configuring-an-asus-router-asuswrt-stock-firmware).

### pfSense

1. Go to **Status → System Logs → Settings**.
2. Set **Log Message Format** to **BSD (RFC 3164, default)**.
3. Under **Remote Logging Options**, tick **Send log messages to remote syslog
   server**.
4. In **Remote log servers**, enter `192.168.1.209:514`.
5. Under **Remote Syslog Contents**, tick **Firewall Events** and
   **System Events** (or **Everything**).
6. Select **Save**. Make sure the firewall rules you care about have
   **Log packets that are handled by this rule** ticked.

### OPNsense

1. Go to **System → Settings → Logging**, then the **Remote** tab.
2. Add a destination: **Transport** `UDP(4)`, **Hostname**
   `192.168.1.209`, **Port** `514`. Leave **Applications** empty to send
   everything, or pick `filter (filterlog)` and `system`.
3. Turn off **rfc5424** if the option is shown.
4. Save and apply. Turn on **Log** for the firewall rules you want recorded.

### Fortinet FortiGate

In the GUI, go to **Log & Report → Log Settings**, turn on **Send logs to
syslog**, and enter `192.168.1.209`. Or use the CLI:

```text
config log syslogd setting
    set status enable
    set server "192.168.1.209"
    set port 514
    set mode udp
    set format default
end
```

Keep `format default`. Its `srcip=`, `dstip=`, and `action=` fields are
recognized, so FortiGate traffic is fully parsed (see
[what gets parsed](#what-gets-parsed)).

### Ubiquiti UniFi

In the UniFi Network application, open **Settings → CyberSecure → Traffic
Logging** (older versions: **Settings → System → Advanced → Remote Logging**).
Turn on **Activity Logging (Syslog)** or **Remote Syslog Server**, choose
**SIEM Server**, and enter `192.168.1.209` and port `514`. For firewall rule
hits, turn on **Syslog Logging** on each rule.

### Cisco Meraki

1. In the Meraki dashboard, go to **Network-wide → General**.
2. Under **Reporting**, select **Add a syslog server**.
3. Enter `192.168.1.209`, port `514`, and choose roles such as
   **Security events**, **Appliance event log**, and **Flows**.
4. Select **Save**.

The dashboard is in the cloud, but the logs are sent by the appliance
itself. The Docker host must be reachable from the Meraki device's network.

### MikroTik RouterOS

In a terminal (WinBox **New Terminal** or SSH):

```text
/system logging action add name=netsecwatch target=remote remote=192.168.1.209 remote-port=514 bsd-syslog=yes
/system logging add topics=firewall action=netsecwatch
/system logging add topics=info action=netsecwatch
/system logging add topics=critical action=netsecwatch
```

Firewall rules are logged only when they have `log=yes`, for example
`/ip firewall filter set [find chain=input action=drop] log=yes`.

### OpenWrt

```bash
uci set system.@system[0].log_ip='192.168.1.209'
uci set system.@system[0].log_port='514'
uci set system.@system[0].log_proto='udp'
uci commit system
/etc/init.d/log restart
```

Or use **System → System → Logging** in LuCI. To log blocked traffic, tick
**Enable logging on this zone** under **Network → Firewall** for the `wan`
zone.

### Cisco IOS routers and switches

```text
configure terminal
 logging host 192.168.1.209 transport udp port 514
 logging trap informational
 service timestamps log datetime msec localtime show-timezone
end
write memory
```

### What gets parsed

Every syslog message is stored and searchable by its text. Some formats are
also split into fields such as `source.ip`, `destination.ip`, and
`event.action`. Those fields drive the network dashboards and the
`firewall-denies-per-source` and `port-fanout-per-source`
[ML jobs](machine-learning.md#run-ml-on-your-real-logs).

| Device or format | Fields extracted | `event.dataset` |
| --- | --- | --- |
| ASUS and other routers whose kernel firewall lines start `DROP`, `REJECT`, or `ACCEPT` with `SRC=`, `DST=`, `PROTO=` | Yes | `asuswrt.firewall` |
| FortiGate and other firewalls sending `key=value` logs with source, destination, and action (`srcip`/`src`, `dstip`/`dst`, `action`) | Yes | `enterprise.firewall` |
| pfSense and OPNsense `filterlog`, MikroTik, UniFi, Meraki, Cisco, and others | Text only: host, program, severity, and message | `syslog.rfc3164` |

For "text only" devices you can still search messages in Discover, use them
in [your own ML job](machine-learning.md#make-your-own-job), and build saved
searches. To get connection fields for them, add a
[traffic sensor](#6-traffic-sensor-zeek-and-suricata). Adding a parser for a
new format is described in [golden parser tests](../golden-parser-tests.md).

### Encrypted syslog (TLS)

Port 6514 accepts RFC 5424 syslog over TLS for devices that support it. It
needs certificates and a collector config change first. Follow
[TLS certificate setup](../network-device-syslog-collection.md#tls-certificate-setup).

## 2. Linux servers

Forward each server's logs with `rsyslog`, which most distributions include.
On each server, create `/etc/rsyslog.d/90-net-sec-watch.conf`:

```text
# Forward all logs to Net Sec Watch over TCP. Messages are queued on disk
# while the collector is unreachable and sent when it comes back.
*.* action(type="omfwd" target="192.168.1.209" port="514" protocol="tcp"
           template="RSYSLOG_TraditionalForwardFormat"
           queue.type="LinkedList" queue.filename="netsecwatch"
           queue.saveOnShutdown="on" action.resumeRetryCount="-1")
```

Then restart rsyslog and send a test line:

```bash
sudo systemctl restart rsyslog
logger "NetSecWatchTest002"
```

Search `NetSecWatchTest002` in Discover (`net-sec-watch-network` data view).
Each server appears under its own `host.name`.

- **Only security logs:** replace `*.*` with `auth,authpriv.*` to forward
  logins, `sudo`, and SSH only.
- **No rsyslog installed** (some minimal images): install it first with
  `sudo apt install rsyslog` or `sudo dnf install rsyslog`.
- **Network devices that run Linux** (NAS boxes, hypervisors, appliances)
  usually have a "remote syslog" setting. Use the
  [router settings](#1-router-or-firewall-syslog) above.

SSH and PAM failures from forwarded servers feed the `auth-failures-per-host`
ML job.

## 3. Logs on the Docker host

To collect the Docker host's own logs instead of the bundled samples, edit
`.env`:

```dotenv
HOST_LOG_ROOT=/var/log
CONTAINER_LOG_ROOT=/var/lib/docker/containers
```

Then run `make up` to restart the collector with the new folders. It reads
`syslog`, `messages`, and `auth.log` from `HOST_LOG_ROOT` and every
container's JSON log from `CONTAINER_LOG_ROOT`, read-only. Host logs go to the
`net-sec-watch-system` data view and container logs to
`net-sec-watch-application`.

- **WSL2:** `/var/log` is the WSL distribution's own log folder, not Windows.
  Use [method 4](#4-windows-computers) for Windows logs.
- **Docker Desktop:** container logs live inside Docker Desktop's VM, so
  `CONTAINER_LOG_ROOT` won't find them. Container log collection needs Docker
  Engine on Linux.
- **systemd-only hosts** (no `/var/log/syslog` or `/var/log/messages`): install
  `rsyslog` so the journal is also written to those files.

## 4. Windows computers

Windows doesn't send syslog by itself. Install a forwarding agent such as
[NXLog Community Edition](https://nxlog.co/products/nxlog-community-edition)
and replace its `nxlog.conf` with:

```text
<Extension syslog>
    Module  xm_syslog
</Extension>

<Input eventlog>
    Module  im_msvistalog
</Input>

<Output netsecwatch>
    Module  om_tcp
    Host    192.168.1.209
    Port    514
    Exec    to_syslog_bsd();
</Output>

<Route windows>
    Path    eventlog => netsecwatch
</Route>
```

Restart the **nxlog** service. Events appear in the `net-sec-watch-network`
data view under the computer's `host.name`, for example a failed logon
contains `An account failed to log on`.

Windows events are stored as text and aren't split into fields. To watch
Windows logon failures with ML, copy the `auth-failures-per-host` template as
[your own job](machine-learning.md#make-your-own-job) with the query
`message:"An account failed to log on"`.

## 5. Application log files

If an application can send syslog, point it at port 514 like a
[Linux server](#2-linux-servers). Otherwise the collector can read its log
files. Two file types are read without any config change:

| Files | Format | Collector folder |
| --- | --- | --- |
| `*.json.log` | One JSON object per line | `/logs/app` |
| `*.log` | Plain text, including multi-line Java stack traces | `/logs/text` |

Map your log folder onto one of those collector folders with a
`compose.override.yaml` file next to `compose.yaml`. Docker Compose reads it
automatically:

```yaml
services:
  fluent-bit:
    volumes:
      - /srv/myapp/logs:/logs/app:ro
```

Then run `make up`. Events go to the `net-sec-watch-application` data view.
The file holds machine-specific paths, so keep it out of Git (it's in
`.gitignore`). For other formats or file names, add an input as described
in [onboard a file source](../onboarding-file-source.md).

## 6. Traffic sensor (Zeek and Suricata)

A sensor watches a copy of the network traffic and records every connection,
DNS lookup, TLS server name, and, with Suricata, IDS alerts. It needs to
receive traffic that isn't addressed to it, so first choose how it gets that
copy:

| Option | How it works | Good for |
| --- | --- | --- |
| Switch mirror (SPAN) port | A managed switch copies the router uplink port to the sensor's port | Most home and small office networks. Needs a switch with port mirroring |
| Network TAP | A small device in the cable between router and switch copies traffic out | Reliable copies without changing switch settings |
| Linux gateway | The sensor runs on the Linux machine that routes the traffic | When your router is already a Linux box |

Mirror the port that connects to your router (the uplink). That covers all
internet traffic. Traffic between two devices on the same switch is only
seen if their ports are mirrored too.

The sensor must run on a Linux machine that has a physical network interface
connected to the mirror port or TAP. Docker Desktop, WSL2, and Wi-Fi
interfaces can't see other devices' traffic.

1. Connect a spare network port on the Linux machine to the mirror port or
   TAP. Find its name with `ip link` (for example `enp2s0`). It doesn't need
   an IP address.
2. Set the interface in `.env`:

   ```dotenv
   ZEEK_INTERFACE=enp2s0
   SURICATA_INTERFACE=enp2s0
   ```

3. Start one or both sensors:

   ```bash
   make up-zeek
   make update-suricata-rules && make up-suricata
   ```

4. Browse a few websites from another device, then search
   `event.module: zeek` or `event.module: suricata` in the
   `net-sec-watch-network` data view.

Sensor data feeds the `port-fanout-per-source` ML job. Sensors record
detailed activity for everyone on the network, so agree on who may see it and
how long to keep it before turning one on. More detail:
[Zeek](../zeek-network-sensor.md), [Suricata](../suricata-ids-sensor.md).

## Check that data is arriving

```bash
make ingestion-status
```

This shows how recently each stream (application, system, network,
dead-letter) received an event. A stream that should have data but shows as
stale or missing points to a broken source.

In Discover, check what each source sends:

| Search (data view `net-sec-watch-network`) | Shows |
| --- | --- |
| `event.dataset: asuswrt.firewall or event.dataset: enterprise.firewall` | Parsed firewall events |
| `host.name: "edge-fw-01"` | Everything from one device or server |
| `event.module: zeek or event.module: suricata` | Sensor events |
| `event.dataset: pipeline.deadletter` | Messages that couldn't be parsed |

Once logs have been arriving for a while, run the ML jobs on them: see
[run ML on your real logs](machine-learning.md#run-ml-on-your-real-logs).
They give better results after about a week of history.

## Troubleshooting

| Problem | Check |
| --- | --- |
| The test message doesn't arrive, even with `nc` on the Docker host | Is the collector running (`make logs`)? Run `docker compose --env-file .env port fluent-bit 5514/udp`, which should print `0.0.0.0:514`. If the host's own rsyslog already uses port 514 (`sudo ss -ulpn 'sport = :514'`), change `SYSLOG_UDP_PORT` and `SYSLOG_TCP_PORT` in `.env` and on your devices |
| A local test works but the device's logs don't arrive | Host firewall (step 3 of [before you start](#before-you-start)), the device uses the wrong IP (not a `172.x` address), or, on Windows, WSL2 UDP forwarding |
| Messages appear as `pipeline.deadletter` | The device sends RFC 5424 or another format. Switch it to BSD or RFC 3164 |
| Messages arrive but have no `source.ip` | The format is stored as text only. See [what gets parsed](#what-gets-parsed) |
| Events appear at the wrong time | Set the device's clock with NTP. RFC 3164 timestamps carry no time zone, so use UTC on the device if you can |
| Some UDP messages are missing under load | UDP can drop messages silently. Use TCP where the device supports it. See [UDP limitations](../network-device-syslog-collection.md#udp-limitations) |
| A Linux server's logs stop | `systemctl status rsyslog` on the server. The queue keeps messages while the collector is down and sends them later |
| No sensor events | The interface name in `.env`, that the mirror port is configured, and `make logs-zeek` or `make logs-suricata` |

## Reference

- [Network-device syslog collection](../network-device-syslog-collection.md):
  ports, record fields, TLS, WSL2, UDP limits, redundant receivers.
- [File and workload log collection](../file-and-workload-log-collection.md).
- [Parser errors and the dead-letter stream](../parser-errors-and-dead-letter.md).
- [Canonical event schema](../canonical-event-schema.md) and
  [network event correlation](../network-event-correlation.md).
