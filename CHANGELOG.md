# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Core: configuration, locking, `monitor` and `block` modes with confirmation and rollback, manual bans, allowlist.
- Blocklists with sanitizing, size and shrink limits, `sha256` checks and daily updates; DHT bootstrap nodes.
- Backends `iptables` + `ipset` and `nft`, chosen from what is installed; a guard that restores the rules.
- Installer and uninstaller, systemd units, backups and a self-check.
- Telegram and Matrix notifications with a retry queue and a daily digest.
- Integrations with Docker, k3s/k8s, ufw and firewalld, and `bb doctor`.
- Dynamic layer: nDPId build, the listener and `bb show flows`.
- `bb status --json` and `bb doctor --json`; `bb log [-f] [-n N]` for the journal and kernel messages.
- Several interfaces for traffic inspection: `--iface eth0,eth1` starts one nDPId process for each.
- IPv4 keeps being blocked, with a warning, on a host whose `ip6tables` cannot use the `raw` table.
- English and Russian interface.
- `bb ban list` shows the manual bans with the time left; `bb allow list` shows the allowlist with the source of each entry.

### Fixed

- List sanitizing also drops an entry that *contains* a private or special-purpose range (for example `172.0.0.0/8` or `100.0.0.0/8`), not only entries inside one.
- Values in notification events are no longer expanded as globs against the working directory.
- `bb notify setup telegram` shows the detected chat ID, warns when several chats wrote to the bot, and asks for confirmation on a terminal.
- The notification queue is read under its lock, and queue IDs include the process ID, so two events in the same second cannot share an ID (and a Matrix transaction ID).
- k3s pod and service ranges are also read from `--cluster-cidr` and `--service-cidr` in the `k3s` service unit.
- The dynamic-layer listener no longer waits for a full 4 KB block of events when `awk` is `mawk` (the default on Debian and Ubuntu): a detected flow is now added within seconds instead of when nDPId disconnects or enough events pile up.
