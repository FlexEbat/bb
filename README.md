# bb

A lightweight, CLI-only tool that blocks BitTorrent, DHT and blocklisted IP ranges on a Linux host or gateway. Blocking happens in the kernel, so the CPU cost is close to zero. No web panel, no database, no heavy IDS.

> **Status:** under development. See [`tech.md`](tech.md) for the full specification.

## Features

- **Blocklists:** import IP/CIDR lists from files or URLs, updated daily by a systemd timer.
- **DHT and trackers:** bootstrap nodes and public tracker lists are blocked as separate sets.
- **Manual bans and allowlist:** ban with an optional TTL; allowlisted addresses are never blocked.
- **Optional DPI layer:** [nDPId](https://github.com/utoni/nDPId) detects BitTorrent flows and a small listener adds them to a set with a TTL.
- **Safe by default:** starts in `monitor` mode (log and count, no dropping), keeps backups, rolls back on errors and refuses to apply empty or suspiciously shrunk lists.
- **Plays well with others:** works alongside Docker, k3s/k8s, ufw and firewalld without touching their rules.

## How it works

`bb` uses what is already installed on your system:

| Found on the system | Backend used |
|---|---|
| `iptables` (nf_tables or legacy) + `ipset` | iptables + ipset |
| `nft` | nftables |
| only `iptables` | installs `ipset`, then iptables + ipset |
| nothing | installs `nftables` |

Rules live in their own chain (iptables backend) or their own table (nft backend), so existing firewall rules stay untouched.

## Requirements

- Linux with systemd and root access
- Debian/Ubuntu (`apt`) or RHEL/Fedora family (`dnf`). Other distributions are not guaranteed.
- `curl` or `wget`, `ip` (iproute2); `python3` only if you enable DPI

## Quick start

```sh
sudo bb install          # detects the backend, installs only what is missing
sudo bb status           # services, set sizes, drop counters
sudo bb doctor           # sanity checks

sudo bb list add example https://example.com/blocklist.txt
sudo bb list update

sudo bb allow 192.168.1.0/24
sudo bb ban 203.0.113.7 --ttl 7d

sudo bb mode block --confirm 60   # switch from monitor to block, auto-revert if not confirmed
```

## Commands

```
bb install [--backend iptables|nft] [--iface IFACE] [--ports RANGE] [--no-dpi]
bb status [--json]            bb doctor [--json]
bb apply                      bb log -f
bb list add|update|rm         bb show flows
bb ban <ip|net> [--ttl 7d]    bb unban <ip|net>
bb allow <ip|net>             bb integrate auto|docker|k8s|ufw|firewalld|status
bb mode monitor|block [--confirm SECONDS]
bb uninstall
```

## Limitations

- DPI blocking is reactive: the first packets of a flow pass before it is classified.
- Encrypted or obfuscated BitTorrent on non-standard ports is detected less reliably.
- Tracker and DHT lists only cover known addresses; clients using cached peers, magnet links or PEX can bypass them.
- eBPF-based CNIs in Kubernetes may bypass netfilter.
- Overly broad blocklists (CDNs, hosting) cause false positives, so start in `monitor` mode.

## Uninstall

```sh
sudo bb uninstall
```

Removes only `bb`'s own chain/table, sets and units. It never flushes the whole ruleset.
