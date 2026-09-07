# Mains Power Monitor for Unraid

Uses a mains-powered Raspberry Pi (for example a Pi-hole host) as a proxy
for mains/network availability while Unraid remains UPS-backed.

Copyright © 2026 Ray Munro. Licensed under the [GNU GPLv3](LICENSE).

## Behaviour

- Pings the configured Raspberry Pi IPv4 address.
- Records an outage after the configured consecutive failure threshold and
  immediately initiates Unraid's native clean shutdown (`powerdown`).
- Persists the pending outage under `/boot/config/plugins/mains-power-monitor/`
  so it survives an Unraid shutdown/reboot.
- Stamps the pending record when Unraid services stop/shutdown during an
  outage. The pending record is written before shutdown is requested.
- On the same boot or a later boot, waits for consecutive successful pings
  and then sends one WARNING-level Unraid notification through configured
  notification agents.
- The recovery report includes loss time, shutdown time when recorded,
  approximate restart time, connectivity-confirmed time, and the
  loss-to-recovery interval.

## Important limitation

If the router, switches, and Pi are all non-UPS-backed, the plugin detects
loss of that mains-powered network path, not mains voltage directly. A
router/switch/Pi reboot can therefore look like a mains outage. If Unraid
is powered off when mains returns, the exact restoration time cannot be
observed.

## Safety note

Reaching the configured failure threshold intentionally shuts Unraid down.
The default is four failed checks.

## Installation

**Via Community Applications:** search for "Mains Power Monitor" in the
Apps tab and click Install.

**Manually:** in the Unraid webGUI go to **Plugins → Install Plugin** and
paste:

```
https://raw.githubusercontent.com/RayMunro/unraid-mains-power-monitor/main/mains-power-monitor.plg
```

or from the terminal:

```bash
plugin install https://raw.githubusercontent.com/RayMunro/unraid-mains-power-monitor/main/mains-power-monitor.plg
```

Then open **Settings → User Utilities → Mains Power Monitor** to configure
the target IP and thresholds. It appears as a compact clickable tile;
clicking it opens the full settings page. Everything the plugin needs is
written by the `.plg` itself, so nothing else needs to be downloaded or
copied by hand.

## Uninstall

From Settings → Plugins, remove "mains-power-monitor" normally, or run:

```bash
plugin remove mains-power-monitor.plg
```
