# Net Scope

Net Scope lists the SmartHome packets that the central OS receives and sends, similar to a small packet analyzer. Install it with `inst app net_scope` on a v49 central computer and open it from Start.

## What it shows

Each row is one packet, newest first: OS uptime in seconds, direction, packet type, client and encoded size.

| Color | Meaning |
| --- | --- |
| Green `<` | Received and accepted by the OS |
| Blue `>` | Sent by the OS |
| Gray | Ignored: a relay-channel duplicate, or a packet addressed to another computer |
| Red | Foreign: text on the OS channels that is not a valid SmartHome packet |

Tap a row for details: sender and recipient computer IDs, client ID, channel, sequence number, relay hops and the packet's fields. Nested tables show as `{count}` and long strings are shortened. **Type** and **Client** return to the list filtered to that value.

**Hold** freezes the list. **Menu** has direction, type and client filters, statistics by type and client, **Clear capture** and the UI color.

## Limits

- The OS modem listens on its server channel and relay channel `65533`. Net Scope sees client-to-OS traffic, OS replies, and relayed copies. It cannot see other channels or Rednet traffic.
- Every sender also transmits a copy on the relay channel. Those copies appear as ignored and are hidden by default.
- Monitor redraw packets are skipped by default. With **Render packets: captured**, every redraw of Net Scope itself adds a row.
- The buffer holds the latest 200 packets in memory. Nothing is saved. Capture runs only while a Net Scope window is open.

## App API

| API | Result |
| --- | --- |
| `api.capturePackets(enabled, skipTypes)` | Starts or stops capture. `skipTypes` is an optional set such as `{render = true}`. Returns whether capture is active |
| `api.getPacketLog()` | `entries, total, active`. Entries are oldest first: `{n, at, direction, status, channel, bytes, type, sender, recipient, clientId, hops, sequence, info}`. Treat them as read-only |
| `api.clearPacketLog()` | Empties the buffer |

`lib_network.lua` calls the optional `net.tap(direction, packet, channel, bytes, accepted)` after a successful send and after every decoded receive.
