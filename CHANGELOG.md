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
- English and Russian interface.
