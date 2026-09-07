# Mains Power Monitor for Unraid

This plugin is a workaround for UPS units that cannot directly report a
mains power failure to the Unraid server. Instead of a power-failure signal
from the UPS, Unraid monitors the IPv4 address of a separate network device
that is powered from normal mains and is **not** protected by an
uninterruptible power supply (UPS), while Unraid itself remains UPS-backed.

Copyright © 2026 Ray Munro. Licensed under the [GNU GPLv3](LICENSE).

## Behaviour

- Pings the configured monitored-device IPv4 address.
- The monitored device must use normal mains power and must not be
  UPS-backed; Unraid itself should remain powered by the UPS.
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

Choose a device with a fixed/reserved IPv4 address that is normally
reliable and powered from the same non-UPS mains supply you want to
monitor — a router, switch, access point, small computer, printer, or
another always-on network appliance, as long as it isn't UPS-backed.

## Important limitation

This plugin does not measure mains voltage and does not receive a hardware
power-failure signal from the UPS. It infers a probable mains outage from
the disappearance of a network device deliberately left off UPS power. A
reboot, failure, cabling problem, or other loss of that device or its
network path can therefore look like a mains outage and can trigger the
configured clean shutdown. If Unraid is powered off when mains returns,
the exact restoration time cannot be observed; the recovery report gives
the time connectivity was confirmed after Unraid restarted.

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
