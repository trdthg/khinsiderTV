# LAN sync (局域网同步)

Cross-device features that need no server, no account and no cloud: devices on
the same WiFi find each other and talk directly.

Implemented in `lib/data/lan/` (transport) and `lib/state/lan_controller.dart`
(app state); the UI is `lib/ui/settings/lan_screen.dart`.

## What it does today

| Feature | State |
| --- | --- |
| Discover other devices running this app on the same network | done |
| Send this device's favorites to another device | done |
| Pull another device's favorites and merge them in | done |
| Add a device by IP (networks that filter broadcasts) | done |
| Synchronised playback / surround-style speaker groups | not yet (see TODO.md S8) |

## Discovery

* Every device binds UDP **41234** and listens.
* `refresh()` broadcasts a `probe` JSON datagram to `255.255.255.255` and to the
  directed broadcast of each private `/24` it sits on (Dart's `NetworkInterface`
  exposes no netmask, and home networks are `/24`). Receiving sides learn the
  HTTP port from the reply.
* A device that hears a `probe` answers `pong` **directly to the sender** and
  also records the sender, so one refresh teaches both sides about each other.
  A `bye` on shutdown removes it immediately.
* Every beacon (`probe` and `pong`) carries `fav`, the sender's favorites count,
  so the device list shows a real number instead of a placeholder 0.
* Discovery only runs while a device list is on screen (every 15s): peers expire
  permanently, so somebody has to keep asking, and nobody else pays for it.
* Peers that have not been heard from for 20 seconds are dropped, so the list
  reflects "around right now" — both apps must be open.
* Manual addresses are just unicast probes; they are remembered in the KV store
  and are never expired.

## HTTP API

All requests must carry `x-khinsider: 1`; anything else gets `403`.

| Method | Path | Meaning |
| --- | --- | --- |
| `GET` | `/kh/info` | id, name, version, favorite count |
| `GET` | `/kh/favorites` | the favorites as JSON (`albumSummaryToJson`) |
| `POST` | `/kh/favorites` | merge (or, with `"mode": "replace"`, overwrite) the body's favorites into this device, reply `{added, total, replaced}` |

`x-khinsider-name` carries the caller's display name so the receiving side can
say who synced.

`mode` is optional and defaults to `"merge"`: an unknown or missing value merges,
because that is the operation that cannot lose data. `"replace"` overwrites the
receiving list with the body, so anything only the receiver had is gone.

### When the connection fails

A peer that answers the UDP broadcast but refuses the TCP connection is the
failure this feature actually sees in the field: the address is right but the
port came from an older beacon, or the device (a TV especially) dropped off the
network and its radio needs a packet to wake up. Every request therefore gets
one recovery attempt: a unicast probe to the same address, which refreshes the
advertised port and gives a sleeping peer a reason to wake, followed by a second
try. If that also fails, the error names the address and port it tried
(`连不上 客厅电视（192.168.1.20:41827）：…`) instead of just the device name,
because "can't connect" without an address is not something a user can act on.

## Security model

Plain HTTP, no authentication, and no TLS (a self-signed certificate would need
pairing UI, and the devices have no way to verify each other). This is
deliberate and its blast radius is small:

* The ordinary sync is a **union merge** of favorites: it cannot delete,
  cannot overwrite, and cannot run anything.
* The two "overwrite" variants (`mode: "replace"`) *can* delete favorites on one
  side. They are only sent after the row is tapped twice in a row, and the
  receiving side needs no extra permission — anyone who can reach the port can
  ask for a merge, which is exactly why an unattended device should keep the
  feature switched off rather than rely on the confirmation.
* Nothing about playback, files or account data is exposed.
* Both devices must have the app open, and the user must start the sync from
  one of them.
* The feature can be switched off entirely in Settings (no sockets are opened
  at all when it is off).

Anyone on the LAN can therefore read the favorites list and add entries to it.
If that is not acceptable on a given network, turn the switch off.

## Platform notes

* **Android**: the app's `network_security_config.xml` opens
  `cleartextTrafficPermitted` in `base-config` — peer addresses come from DHCP,
  so they cannot be listed by name. Internet traffic is HTTPS regardless.
* **iOS**: `NSLocalNetworkUsageDescription` is set, which is what triggers the
  iOS 14+ local network permission prompt.
* **macOS**: needs `com.apple.security.network.client` **and**
  `com.apple.security.network.server` in the entitlements (both are already
  there, the latter for just_audio's local proxy).
* **Windows**: the first launch may raise a firewall prompt.
