---
display_name: Avahi mDNS
icon: /icon/network.svg
description: Advertise workspace hostnames on the local network
verified: false
tags: [network, mdns, avahi]
---

# Avahi mDNS

Install `avahi-daemon` and enable its systemd service at workspace startup. Avahi advertises the system hostname as `<hostname>.local` and updates address records when IP addresses change. No static IP or DNS record needed.

```tf
module "avahi" {
  source   = "github.com/shekohex/hakim//coder/modules/avahi?ref=main"
  agent_id = coder_agent.main.id
}
```

| Variable | Description | Default |
|----------|-------------|---------|
| `agent_id` | Coder agent ID | Required |
| `enabled` | Install and run Avahi; stop and disable its service/socket when false | `true` |

Requires Debian/Ubuntu, systemd, and passwordless sudo. Uses the existing hostname and Avahi defaults; does not change network or firewall configuration.

Clients need mDNS support and multicast connectivity to the workspace on UDP 5353. A bridged Proxmox workspace on the same LAN fits; private Docker networks, NAT, and hosted GitHub Actions runners are not automatically reachable from the LAN.

## Usage

Find the advertised name inside the workspace:

```bash
echo "$(hostname).local"
```

From another device on the same LAN, use that hostname with the desired service port, for example `http://coder-shekohex-raptors.local:3157/`.

Name conflicts may cause Avahi to choose a suffixed hostname. Inspect the service and its announcements:

```bash
sudo systemctl status avahi-daemon.service
sudo journalctl -u avahi-daemon.service -f
```

See [Avahi configuration reference](https://github.com/avahi/avahi/blob/master/man/avahi-daemon.conf.5.xml.in) for hostname, domain, and address publishing defaults.
