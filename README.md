# bb

A lightweight, CLI-only tool that blocks BitTorrent, DHT and blocklisted IP ranges on a Linux host or gateway. Blocking happens in the kernel, so the CPU cost is close to zero. No web panel, no database, no heavy IDS.

> **Status:** under development. See [`tech.md`](tech.md) for the full specification.

## Features

- **Blocklists:** import IP/CIDR lists from files or URLs, updated daily by a systemd timer.
- **DHT and trackers:** bootstrap nodes and public tracker lists are blocked as separate sets.
- **Manual bans and allowlist:** ban with an optional TTL; allowlisted addresses are never blocked.
- **Optional DPI layer:** [nDPId](https://github.com/utoni/nDPId) detects BitTorrent flows and a small bash listener (parsing events with `jq`) adds them to a set with a TTL.
- **Notifications:** optional Telegram and Matrix alerts (mode changes, failed or rejected list updates, guard restores, service failures, daily digest), sent with plain `curl`.
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
- `curl` or `wget`, `ip` (iproute2). No Python or other interpreters needed: everything is bash plus standard tools. `jq` is installed only when needed (DPI, Matrix notifications, `--json` output).

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

sudo bb notify setup telegram     # or: matrix
sudo bb notify test
```

## Commands

```
bb install [--backend iptables|nft] [--iface IFACE] [--ports-mode only|all|except]
           [--ports LIST] [--no-dpi] [--yes]
bb migrate                    migrate from BitBlocker
bb status [--json]            bb doctor [--json]
bb apply                      bb log -f
bb list add|update|rm         bb show flows
bb ban <ip|net> [--ttl 7d]    bb unban <ip|net>
bb allow <ip|net>             bb integrate auto|docker|k8s|ufw|firewalld|status
bb notify setup telegram|matrix | test | status | enable | disable
bb mode monitor|block [--confirm SECONDS]
bb uninstall
```

## Notifications

Telegram needs a bot token and a chat ID. Matrix needs a homeserver URL, an access token and a room ID (unencrypted rooms only; messages are built with `jq`). Secrets are stored in `/etc/bb/notify.conf` (root, mode 0600) and never appear in logs or the process list. Duplicate events are suppressed and the message rate is limited. A failed delivery never affects the firewall: messages are queued and retried.

## Limitations

- DPI blocking is reactive: the first packets of a flow pass before it is classified.
- Encrypted or obfuscated BitTorrent on non-standard ports is detected less reliably.
- Tracker and DHT lists only cover known addresses; clients using cached peers, magnet links or PEX can bypass them.
- eBPF-based CNIs in Kubernetes may bypass netfilter.
- Notifications depend on external services, and Matrix end-to-end encrypted rooms are not supported.
- Overly broad blocklists (CDNs, hosting) cause false positives, so start in `monitor` mode.

## Uninstall

```sh
sudo bb uninstall
```

Removes only `bb`'s own chain/table, sets and units. It never flushes the whole ruleset.
