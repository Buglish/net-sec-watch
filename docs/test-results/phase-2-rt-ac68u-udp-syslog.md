# Phase 2 RT-AC68U UDP Syslog Verification

Author: SJ du Preez

## Objective

Verify that a stock ASUS RT-AC68U can send system and selected firewall events
to Net Sec Watch through UDP syslog, and confirm that the documented visibility
limitations are understood.

## Result

Pass. The RT-AC68U produced UDP syslog records that were received by Fluent Bit
and normalized with the expected syslog and network metadata fields.

This completes the Phase 2 completion gate:

> The RT-AC68U sends system and selected firewall events through UDP syslog, and
> the documented limitations are verified.

## Evidence observed

The router was configured from **System Log → General Log → Remote Log Server**
with the Windows host LAN address only. Stock Asuswrt sends remote syslog over
UDP port 514 automatically, so the router field did not include a port or
protocol suffix.

Observed system records included router service events such as:

- `kernel: klogd started`
- `rc_service: httpd ... notify_rc restart_logger`

Observed firewall records included kernel drop events such as:

- `DROP IN=eth0 OUT= ... PROTO=UDP ... DPT=6667`

The received records included the expected normalized fields:

- `event.original`
- `event.receive_time`
- `host`
- `ident`
- `message`
- `net.src_ip`
- `net.transport: udp`
- `log.syslog.facility.*`
- `log.syslog.severity.*`

The ASUS firewall drop parser also preserves firewall-event details where the
firmware supplies them, including source address, destination address, protocol,
source port, destination port, ingress interface, and drop/deny action.

## Verified limitation

RT-AC68U syslog is useful for system, authentication, wireless, DHCP, and
selected firewall events, but it is not a complete network-flow feed. It does
not provide every connection crossing the network, full packet context, or
decrypted TLS payloads.

For broader traffic visibility, Net Sec Watch requires a Zeek or Suricata
sensor placed on a mirrored/SPAN port, network TAP, or gateway interface.

## Follow-up gates still open

The following Phase 2 completion gates still require live environment evidence:

- A selected enterprise router or firewall sends searchable events through
  TCP/TLS.
- At least one Zeek or Suricata sensor produces searchable connection metadata
  from mirrored, tapped, or gateway traffic.
