# bb — a lightweight CLI blocker for BitTorrent, DHT and blocklists

## 1. Purpose

`bb` is a command-line tool for a Linux host or gateway that blocks BitTorrent traffic, DHT and addresses from arbitrary blocklists. Blocking is done in the kernel by the firewall that is already installed on the system. All that remains on the outside is one bash script, a small bash daemon (DPI only) and systemd units. Python and other interpreters are not needed.

Goals:

- **minimum packages:** `bb` uses what is already on the system and installs only what is missing;
- simple installation and setup: a single `bb install` command;
- no web panels, no databases, no heavy IDS (Suricata is not used);
- peaceful coexistence with Docker, k3s/k8s, ufw and firewalld: `bb` does not touch other tools' rules;
- safe by default: the system must not cut the administrator off from the machine;
- notifications about important events to Telegram and Matrix via plain `curl` (section 9);
- the interface is fully in English or fully in Russian, chosen at install time (section 10).

Non-goals: a full SIEM, a web interface, analysis of protocols other than BitTorrent, managing a whole cluster, blocking encrypted P2P with 100% accuracy.

## 2. Platforms and requirements

| Family | Package manager | Status |
|---|---|---|
| Debian, Ubuntu and derivatives | `apt` | supported, tested |
| RHEL, Fedora, Rocky, Alma and derivatives | `dnf` | supported, tested |
| Others (Arch, Alpine, openSUSE, etc.) | — | not guaranteed |

Platform detection: from `/etc/os-release` (`ID`, `ID_LIKE`). If the family cannot be determined, `bb install` stops with a message and a list of dependencies for manual installation. The `--force` flag skips the check with no guarantees.

### What is required and where it comes from

| What | Source | Installed separately? |
|---|---|---|
| systemd, bash 4+, `flock` (util-linux), `getent` (glibc) | base system | no, only checked for |
| `ip` (iproute2) | almost always in the base system | only if missing |
| `curl` (or `wget`, if already present) | usually present | only if neither is present |
| firewall backend (section 3) | whatever is already installed | only if none is found |
| `awk`, `sed`, `grep` | base system | no, only checked for |
| `jq` | standard apt and dnf repositories | on demand only: DPI, the Matrix channel, `--json` mode |

Not required: `python3` and other interpreters, `dig`/`host` (names are resolved with `getent ahosts`), rule persistence packages (`ipset-persistent`, `netfilter-persistent`, `ipset-service`), `gettext` (translations are plain bash catalogs, see section 10). In the basic mode (no DPI, no Matrix, no `--json`) `jq` is not needed either and is not installed.

## 3. Backend selection: use what is installed

`bb` has two backends with identical external behavior and CLI. The choice is made automatically at install time (the `--backend iptables|nft` flag sets it manually), the result is written to `bb.conf`, and `bb doctor` re-checks it.

Detection:

- **iptables:** the `iptables` command exists (and `ip6tables`, if IPv6 is enabled). The variant is determined from `iptables -V`: `(nf_tables)` means the `iptables-nft` wrapper, `(legacy)` means classic xtables. Both variants are supported equally;
- **ipset:** the `ipset` command exists and the kernel provides the `ip_set` module;
- **nft:** the `nft` command exists and `nft list tables` works.

Selection order:

1. both iptables **and** ipset found → the `iptables` backend (iptables + ipset);
2. otherwise nft found → the `nft` backend, nothing needs to be installed;
3. iptables found, but neither ipset nor nft → **one** package, `ipset`, is installed, backend `iptables`;
4. nothing found → **one** package, `nftables`, is installed, backend `nft`. This is the shortest path (native sets, no ipset needed); the behavior is changed with `install_backend=iptables` (then `iptables`/`iptables-nft` and `ipset` are installed).

If both backends are present, `iptables` has priority (for example, on Debian 13 with `iptables 1.8.x (nf_tables)` a separate `nftables` package is not needed).

A note on `iptables (nf_tables)`: it is only a wrapper program over the same kernel nf_tables. In this mode `bb` rules are also visible in `nft list ruleset` (as tables managed by iptables-nft). They must not be changed through nft, and `bb` does not do so.

## 4. Architecture

Two independent layers.

1. **Static layer (lists).** IPs and networks from blocklists live in sets (ipset or nft sets), and the kernel drops packets that match them.
2. **Dynamic layer (DPI, optional).** The nDPId daemon detects BitTorrent from flow content, and the listener adds detected flows to a set with a TTL.

The dynamic layer is attached last: the system is useful without it.

## 5. Components

| Component | Role | Load |
|---|---|---|
| `bb` (bash) | installation, configuration, management, backend abstraction layer | on demand only |
| sets + rules (iptables/ipset or nft) | blocking | in the kernel, minimal |
| `bb-update.timer` | refresh of lists and DHT nodes | once a day |
| `bb-guard.timer` | checks that the rules are in place and first in order, refreshes integration subnets | every few minutes, milliseconds |
| nDPId (optional) | flow capture and classification | low, depends on traffic |
| listener (bash + `jq`) | reads nDPId JSON events, adds flows to a set in batches | almost zero |
| `bb notify` (bash + `curl`) | notifications to Telegram and Matrix | only on events |

All firewall-facing code is concentrated in a set of abstraction-layer functions (`fw_init`, `fw_apply`, `set_replace`, `set_add`, `set_del`, `fw_status`, `fw_remove`). The rest of the code does not depend on the chosen backend.

## 6. Blocking implementation

### 6.1. Common logic (both backends)

Sets exist for each address family (4 and 6; IPv6 is enabled with `ipv6=yes`, on by default if the host has IPv6):

| Set | Contents | Purpose |
|---|---|---|
| `allow4/6` | addresses and networks | exceptions, never blocked |
| `manual4/6` | addresses and networks, with timeout | manual bans |
| `list4/6` | addresses and networks | external lists and trackers |
| `dht4/6` | "address and port" pairs | DHT bootstrap nodes |
| `flow_src4/6`, `flow_dst4/6` | "address and port" pairs (`address,udp:port`), with timeout (24 h) | dynamic flows from nDPId: source and destination are kept in two sets (in the nft backend this is a single `flow` set holding the tuple "address, port, address, port") |

Check order:

1. loopback → pass;
2. `allow` (by source and destination) → pass (leave the `bb` chain);
3. `manual` → drop;
4. `list` → drop;
5. `dht` (UDP) → drop, taking the port mode into account (section 11);
6. `flow` → drop: a packet is dropped if its source is in `flow_src` and its destination is in `flow_dst`, or the other way round (the reply direction). A pair of sets instead of one blocks by the tuple "address, port, address, port" rather than by a single address and port, which reduces collateral blocking.

Important: "pass" only means "do not apply `bb` blocking". The rules of ufw, firewalld, Docker and k8s keep working, and the `bb` allowlist does not cancel their denies.

**`monitor` mode:** instead of drop, a rule with a counter and rate-limited logging (`log prefix "bb: "`) is used; packets are not dropped.

**Atomic update and protection against "bad" lists:** a set is first filled in a temporary instance and then swapped in (ipset swap or an nft transaction). If the download fails, or the list is empty or has shrunk sharply (threshold `min_list_ratio`, 50% of the previous size by default), the old set is kept.

**After a reboot:** in the iptables backend, the `bb-sets.service` unit creates the sets from the cache in `/var/lib/bb` (without network access) before the other firewall services, then `bb-firewall.service` applies the rules (the ordering is explained in section 6.2). In the nft backend a single `bb-firewall.service` is enough.

### 6.2. The `iptables` + `ipset` backend

- ipset sets: `bb_allow4`, `bb_manual4`, `bb_list4` (`hash:net`), `bb_dht4`, `bb_flow_src4`, `bb_flow_dst4` (`hash:ip,port`), with `family inet6` for IPv6; `maxelem` and `hashsize` are set explicitly (`list_maxelem`, 1,048,576 by default) because the default value (65,536) is too small for large lists;
- the rules live in the user-defined chain `BB_FILTER` of the **raw** table, hooked as the first rule in `PREROUTING` and `OUTPUT`. The raw table is chosen because its rules run before conntrack and DNAT, do not bloat conntrack and see the original addresses;
- the chain is rebuilt in a single transaction with `iptables-restore --noflush` (`ip6tables-restore` for IPv6) using the xtables lock wait option (`-w`), so protection never disappears even for a moment. The `-j BB_FILTER` jump is added only after the chain is created; the number of jumps in `PREROUTING` and `OUTPUT` is checked and must be exactly one (duplicates are removed and the jump is inserted first);
- **jump position.** Other tools (Docker, Calico, etc.) may insert their own rules at the top of raw. Since `ACCEPT` in raw can bypass the rest of the table's rules, `bb-guard` checks that the jump to `BB_FILTER` is first and puts it back if necessary;
- sets are updated with `ipset restore` into a temporary set followed by `ipset swap`;
- dynamic sets are saved to `/var/lib/bb` when the unit stops (`ExecStop`) and restored on start;
- **saved rules.** `bb` itself does not save rules to disk. But if the administrator ran `netfilter-persistent save` or similar, `iptables-restore` fails entirely at boot while the sets do not exist yet. Therefore `bb-sets.service` starts before `netfilter-persistent`, `iptables`, `ip6tables` and `ufw`. Those services replace whole tables, so `bb-firewall.service` starts after them and puts the chain back. `bb doctor` warns if the saved rule files reference `bb` objects.

### 6.3. The `nft` backend

- a dedicated table `inet bb`: rules and chains are shared by IPv4 and IPv6, but the sets remain separate (`ipv4_addr` and `ipv6_addr`), so the `4/6` pairs are kept;
- dynamic flows are stored in a single set with the concatenation "address . port . address . port" and a timeout, so the `flow_src`/`flow_dst` pair is not needed;
- base chains `prerouting` and `output` (`type filter`) with priority **-310** (the `hook_priority` parameter) call the common chain `bb_main`. The priority is earlier than `raw` (-300), conntrack (-200) and DNAT (-100), so `bb` runs before the rules of Docker, firewalld, ufw and kube-proxy; the order is given as a number rather than the word `raw` so that it is deterministic;
- the structure is created with `add` commands (idempotent, set contents are not wiped); rules are rebuilt by a `flush chain` + new rules transaction in a single `nft -f`; `nft -c -f` validation runs before applying;
- sets with lists are replaced by a `flush set` + `add element` transaction in a single `nft -f`;
- `bb` does not modify other tools' tables; `nft flush ruleset` is never used.

### 6.4. Dynamic layer: nDPId and listener (no Python)

The protocol details below are re-verified whenever the nDPId version changes.

- **Connection.** nDPId is started with `-c <path to a unix socket>` and connects by itself to the socket that the listener serves. The intermediate nDPIsrvd daemon is not needed. The interface is set with `-i`; the capture BPF filter uses a separate flag whose name differs between versions and is detected from the `nDPId -h` help output (section 11).
- **Framing.** Each message is 5 decimal digits of length followed by JSON. The length is validated (limit `max_event_size`, 1 MiB by default); on an invalid header the connection is closed and nDPId reconnects.
- **Socket without `socat` or `nc`.** The `bb-listener.socket` unit (systemd socket activation: `ListenStream=/run/bb/ndpid.sock`, `Accept=yes`, `SocketMode=0600`, `MaxConnections=4`) starts a `bb-listener@.service` instance for each connection, whose stdin and stdout are the socket itself (`StandardInput=socket`). Bash does not have to open the socket, the socket is available immediately, and nDPId can be started in any order.
- **Frame parsing.** Bash with `LC_ALL=C` (so that character counting matches bytes) reads `read -N 5`, then `read -N <length>`, and passes clean JSON objects to a single long-lived `jq --unbuffered -c` process (the pipeline "frame parsing → `jq` → apply").
- **`jq` filter.** Events whose `flow_event_name` is `detected` or `detection-update` are taken. The `guessed` event, where the protocol was determined by port, is ignored as unreliable. Conditions: the `ndpi.proto` field contains `bittorrent` (case-insensitive), `l4_proto` is `tcp` or `udp`, `src_ip` and `dst_ip` are of the same family, ports are 1–65535. The output is compact lines "family, source, destination" with elements of the form `address,protocol:port`.
- **Validation twice:** in `jq` (IPv4/IPv6 patterns, port range) and once more in bash before applying. Other strings from events (SNI, host names, etc.) are untrusted and are never substituted into commands.
- **Batched application:** accumulated additions are applied every few seconds in a single call (`ipset restore -exist` with the `flow_ttl` timeout, or a single `nft -f -` transaction).
- **Deduplication:** an associative array "flow → time until which repeated events are ignored" (`flow_dedup`, 600 s by default). After the window the entry is refreshed and the TTL extended. The array size is capped (100,000 entries); when full it is cleared, so memory does not grow.
- **Protection:** addresses from the allowlist and private ranges never enter `flow`; the number of new entries per minute is limited (`flow_rate_limit`); when exceeded, the listener pauses and sends a `rate_limit` notification.
- **Resilience:** corrupted, truncated and oversized messages are skipped or close the connection (see above), nDPId reconnects, and `bb-listener.socket` stays active.
- **Why `jq`:** it is a real parser from the standard repositories, one small package, installed only when needed. A home-grown awk parser (hard to maintain, mawk vs gawk differences) and a separate Go or C binary (building and distributing for different architectures contradicts the "bash and repository packages" goal) were considered and rejected.

## 7. Lists

**Static** (files and URLs):

- DHT bootstrap nodes, resolved by a timer. Each node is given as a "name:port" pair (for example `router.bittorrent.com:6881` and `dht.libtorrent.org:25401`) because node ports differ. Private and special-purpose addresses (including IPv4-mapped IPv6) are dropped from the result and duplicates are removed;
- public trackers (for example ngosang/trackerslist, IPs or hosts);
- P2P activity blocklists and any custom network lists;
- the manual list (`bb ban`).

**Dynamic** (from nDPId): flows detected as BitTorrent, in both directions, TTL 24 h.

**Allowlist**: gateway, DNS, administrator addresses. It is checked before any blocking. At install time the default gateway, the DNS servers from the system configuration and the IP of the current SSH session are added automatically. Integrations (section 8) add container and cluster subnets.

List file format: one entry per line (IP or CIDR), lines starting with `#` and empty lines are ignored, hosts are resolved on update.

List sanitizing: private and special-purpose ranges (RFC 1918, 100.64.0.0/10, loopback, link-local, ULA `fc00::/7`) are removed from external lists unless `strip_private=no`. This keeps container and cluster networks from being blocked.

## 8. Integrations

General principle: `bb` does not modify the rules or configuration of Docker, k8s, ufw and firewalld. It (1) works in its own objects (the `BB_FILTER` chain in raw or the `inet bb` table), (2) adds the necessary subnets to `allow`, (3) checks compatibility with `bb doctor`. Management: `bb integrate auto|docker|k8s|ufw|firewalld|status`. The default mode is `auto` (detection at install time and refresh by the `bb-guard` timer).

### 8.1. Docker

- Docker (iptables) creates its own chains (`DOCKER`, `DOCKER-USER`, NAT) and puts some rules in raw. `bb` rules run before DNAT, so published ports and container traffic are blocked by the original address. Rules in `DOCKER-USER` are not used.
- Docker network subnets (`docker0`, `br-*`) are added to `allow` automatically, detected from interfaces and, if available, via `docker network inspect`. The list is refreshed by a timer.
- On start and restart Docker may insert its own rules at the top of raw: this is covered by the position check (section 6.2). Restarting Docker does not remove the `bb` sets and chain.
- `bb-firewall.service` starts before `docker.service` (ordering only, no hard dependency).

### 8.2. k3s / k8s

- `bb` is installed on each node separately. Centralized cluster management is out of scope.
- kube-proxy modes (iptables, ipvs, nftables) do not matter: they have their own chains and tables.
- Added to `allow`: pod CIDR, service CIDR and node IPs. Detection is automatic where possible: for k3s from `/etc/rancher/k3s/config.yaml` and `config.yaml.d/` (defaults 10.42.0.0/16 and 10.43.0.0/16), for kubeadm from the `kube-controller-manager` manifests, and node addresses if `kubectl` is available. Whatever cannot be detected is set manually (`k8s_pod_cidr`, `k8s_service_cidr`, `bb allow`).
- Internal traffic between nodes (API server, etcd, VXLAN/WireGuard CNI) flows between node addresses, which are in the allowlist.
- NodePort and inbound traffic are visible by the original address before DNAT.
- Calico and some other CNIs insert their rules at the top of raw: covered by the position check.
- Limitation: eBPF-based CNIs (Cilium in kube-proxy replacement mode, Calico eBPF) may bypass netfilter, and blocking for that part of the traffic is not guaranteed.

### 8.3. ufw

- ufw uses `ufw-*` chains in the filter table. `ufw enable/disable/reload` does not affect the `BB_FILTER` chain (or the `inet bb` table).
- `bb allow` only exempts an address from `bb` blocking. Allowing rules (ports, SSH) remain on the ufw side, and vice versa: a `ufw allow` rule does not cancel `bb` blocking. Therefore the `bb` allowlist is mandatory for administrator addresses.
- `bb integrate ufw` only checks status and compatibility; ufw rules are not changed.

### 8.4. firewalld

- firewalld (nftables backend) keeps the tables `inet firewalld`, `ip firewalld`, `ip6 firewalld` and recreates only them on `--reload`. `bb` objects stay untouched. With `FirewallBackend=iptables` the integration also works independently.
- The order relative to firewalld's raw chain (rpfilter, helpers) does not matter: denies from different tables add up, and the `bb` allowlist does not bypass firewalld denies.
- `bb` does not manage zones or rich rules.

### 8.5. Other sources of conflict

- **`nftables.service`.** In Debian the default `/etc/nftables.conf` starts with `flush ruleset`: restarting the service wipes **all** nf_tables tables, including iptables-nft tables (that is, both the `BB_FILTER` chain and the Docker and ufw rules) and `inet bb`. `bb` does not use this service and does not edit `/etc/nftables.conf`. The `bb-firewall.service` unit starts after `nftables.service`, `bb doctor` warns about `flush ruleset` when the service is enabled, and `bb-guard.timer` restores the `bb` rules if they disappear. For the iptables backend in legacy mode the problem does not apply.
- **fail2ban, CrowdSec, Tailscale** and similar: they use their own chains or tables and do not conflict; `bb doctor` lists the detected objects.

## 9. Notifications (Telegram and Matrix)

Optional notifications about important events. They are implemented with `curl` (HTTPS), with no separate daemons. Telegram works without extra packages; Matrix needs `jq` (correct JSON building). Both channels can be enabled at the same time.

**Channels**

- **Telegram:** Bot API, the `sendMessage` method. A bot token and a `chat_id` (private chat, group or channel) are required. The text is sent without markup (`parse_mode` is not used), parameters are passed with `--data-urlencode`.
- **Matrix:** Client-Server API, the request `PUT /_matrix/client/v3/rooms/<room_id>/send/m.room.message/<txn_id>` with an `m.text` message. A homeserver URL, an access token and a room ID are required. A dedicated bot user is recommended. Only unencrypted rooms are supported (E2EE is not supported).

**Events** (the list is set by `notify_events`, ★ — enabled by default)

| Event | When |
|---|---|
| ★ `mode_changed` | monitor/block mode change, including the automatic rollback after a missed confirmation |
| ★ `guard_restored` | the rules disappeared or were displaced and `bb-guard` restored them |
| ★ `list_update_failed` | a list download failed |
| ★ `list_rejected` | a list was rejected by the protection (empty or shrunk sharply) |
| ★ `service_failed` | a `bb` unit failed (via `OnFailure=`) |
| ★ `rate_limit` | the DPI flow addition limit was hit |
| `integration_changed` | the integrations' subnet allowlist was changed automatically |
| `manual_change` | `bb ban`, `bb unban`, `bb allow` were run |
| `digest` | daily summary: mode, backend, set sizes, packets dropped over the day, list update results, errors |
| `install`, `uninstall` | installation and removal |

Individual DPI blocks are not sent one by one; they appear only in the digest.

**Flood protection**

- identical events are suppressed for `notify_dedup` (30 minutes by default);
- a global limit of `notify_rate_limit` messages per hour; beyond it a single "N notifications suppressed" message is sent.

**Reliability**

- notifications are best effort: a delivery failure (no network, wrong token) never blocks or rolls back firewall operations; the send timeout is 10 seconds and sending runs in the background;
- undelivered messages go to a bounded queue `/var/lib/bb/notify.queue` and are retried by the `bb-guard` timer; messages older than `notify_queue_ttl` are discarded;
- the addresses of `api.telegram.org` and the Matrix homeserver are resolved automatically and added to the allowlist (`notify_allow=yes`) so that blocklists do not cut off the notification channel; `notify_proxy` (http, https, socks5) is supported for curl.

**Security**

- tokens are stored in `/etc/bb/notify.conf` (owner root, mode 0600) and do not appear in the journal or in the output of `bb status` and `bb doctor`;
- the URL with the token and the headers are passed to curl through a configuration on stdin (`curl -K -`), so they are not visible in the process list;
- Matrix JSON is built with `jq -n --arg`, that is, with correct escaping of any characters and without manual string concatenation; user data (list names, etc.) is treated as untrusted;
- message format: `[hostname] event: short text`, mode and backend; the text is in the selected interface language (the `lang` parameter, overridable with `notify_lang`), while event identifiers are always English; no tokens and no lists of IP addresses.

**Setup:** `bb notify setup telegram|matrix` (interactive, verified with a test message). For Telegram the helper can determine the `chat_id` via `getUpdates` (requires `jq`) after the user has written to the bot.

## 10. CLI

```
bb install [--lang en|ru] [--backend iptables|nft] [--iface IFACE]
           [--ports-mode only|all|except] [--ports LIST] [--no-dpi] [--yes] [--force]
bb status [--json]               services, set sizes, drop counters, backend
bb doctor [--json]               diagnostics (see below)
bb apply                         rebuild the rules from the configuration
bb lang [en|ru]                  show or change the interface language
bb list add <name> <url|file>    add a blocklist
bb list update [name]            update manually
bb list rm <name>
bb ban <ip|net> [--ttl 7d]       manual ban
bb unban <ip|net>
bb allow <ip|net>                exception
bb integrate auto|docker|k8s|ufw|firewalld|status
bb notify setup telegram|matrix  set up a notification channel
bb notify test                   send a test message
bb notify status                 channels, events, queue size
bb notify enable|disable
bb show flows                    what was blocked by DPI
bb log -f                        event log
bb mode monitor|block [--confirm 60]
bb uninstall
```

General rules: commands that change the system require root; exit code 0 on success, non-zero on error with a message on stderr; every subcommand has `--help`; all state-changing commands take a lock (section 13); every command accepts the global `--lang en|ru` flag. `--json` mode is built with `jq`; if it is missing, an installation hint is printed.

**`bb mode`**: `monitor` mode writes to the log and keeps counters but does not drop (the default after installation). With `bb mode block --confirm N` the mode rolls back to `monitor` if the administrator does not confirm it within N seconds (60 by default, rollback via a transient `systemd-run` timer).

**`bb doctor`** checks: the selected backend and the presence of the required utilities and kernel modules; the iptables variant (nf_tables or legacy); the presence of the `bb` chain or table and the jump position; the state of units and timers; a non-empty allowlist (gateway, DNS, SSH IP); whether `nftables.service` is enabled and whether its configuration contains `flush ruleset`; the status of Docker, k3s/k8s, ufw, firewalld; on dnf systems, SELinux and recent AVC denials for `bb`; the permissions of `/etc/bb/notify.conf` and the notification queue size; the language catalogs (both present, selected language available).

### Interface language

- **Languages.** English (`en`, the default and the fallback) and Russian (`ru`). The whole user-facing interface is shown in the selected language: install wizard prompts, command output, `--help`, errors and warnings, `bb doctor` and `bb status` text, confirmation prompts, progress indicators and notification texts (section 9). Mixing languages within one run is not allowed.
- **Choice at install time.** The language is the first step of the install wizard, before any other question. The prompt itself is bilingual ("Language / Язык: 1) English 2) Русский"). The suggested default comes from `LC_ALL`/`LANG` (`ru*` suggests Russian, anything else English). In non-interactive mode `--lang en|ru` is used, otherwise English. The choice is stored as `lang` in `bb.conf` and can be changed later with `bb lang en|ru`.
- **Precedence:** the `--lang` flag, then the `BB_LANG` environment variable, then `lang` in `bb.conf`, then English.
- **Implementation.** Message catalogs are plain bash files `/usr/share/bb/lang/en.sh` and `ru.sh` that fill an associative array `MSG[key]` with printf-style placeholders; all output goes through a single function `t key [args...]`. No gettext and no extra packages. No user-visible string is hard-coded in the code. A key missing from `ru` falls back to English (and is reported by tests). Plural forms are avoided by phrasing ("Entries: N") because Russian plural rules are complex.
- **Not translated** (stable for scripts and support): command names, flags, configuration keys and values, event identifiers (`mode_changed`, etc.), `--json` keys and values, exit codes. Journal entries and `bb log` output also stay in English with stable event tags, so searching and support work the same in both languages.
- **Terminal encoding.** Russian output requires a UTF-8 terminal. If Russian is selected but the locale is not UTF-8 (for example `LANG=C`), `bb` warns (in English) and offers to switch to English; in non-interactive mode it falls back to English. The progress spinner uses ASCII characters only.
- **Tests:** a catalog parity check (every key exists in both files with the same number and order of placeholders), a lint that finds hard-coded user-visible strings outside the catalogs, and CLI smoke tests run in both languages (section 16).

## 11. Installation

`bb install` performs these steps:

1. language selection (the first wizard step, see section 10); in non-interactive mode `--lang` or English is used;
2. root check, OS family detection (`apt` or `dnf`);
3. backend detection by the rules of section 3 and a printed plan ("X is installed, Y will be installed");
4. installation of missing packages (if any);
5. creation of sets and rules in `monitor` mode;
6. installation of systemd units and timers;
7. filling the allowlist (gateway, DNS, SSH IP) and running `bb integrate auto`;
8. verification (`bb doctor`): rules applied, access not lost;
9. optional: installation of nDPId and the listener (bash), notification setup (`bb notify setup`).

### Packages `bb` may install

Only what is missing is installed (checked with `command -v`, then `dpkg -s` / `rpm -q`):

| What | apt (Debian/Ubuntu) | dnf (RHEL/Fedora) | When |
|---|---|---|---|
| ipset | `ipset` | `ipset` | iptables present, neither ipset nor nft |
| nftables | `nftables` | `nftables` | neither iptables nor nft found |
| iptables (with `install_backend=iptables`) | `iptables` | `iptables-nft` | only on explicit choice |
| curl | `curl` | `curl` | neither curl nor wget present |
| iproute2 | `iproute2` | `iproute` | no `ip` command |
| jq | `jq` | `jq` | DPI enabled, Matrix channel, or `--json` mode needed |

Installation: `apt-get install -y <packages>` and `dnf install -y <packages>`. If installation fails, `bb install` stops before any rule is changed.

### Install wizard and port modes

- `bb install` without flags on a terminal starts a wizard: the language first, then the analysis interface (detected from the default route by default; the name is validated against `^[A-Za-z0-9_.:@-]+$`), the port mode and the port list. Flags and `--yes` are available for automation. On reinstall the previous values are offered as defaults (Enter keeps them).
- Port modes: `only` — nDPId analyzes only the given ports, `all` — all traffic, `except` — all traffic except the given ports. The mode determines the capture BPF filter (`(tcp or udp) and (port … or portrange …)` or `not (…)`) and the DHT rule: in `only` mode DHT is blocked only for the given ports, in `except` mode the given ports are excluded.
- Port list validation: format `6881-6889,51413`, numbers 1–65535, ranges ascending; in the iptables backend at most 15 multiport slots (a range takes two).

### nDPId: building

- nDPId is not in the standard repositories, so it is built from source: `git clone --recursive`, `cmake -DBUILD_NDPI=ON -DBUILD_EXAMPLES=OFF`, `make -j"$(nproc)"`. The binary is copied to `/usr/local/bin/bb-ndpid` and the build directory is removed.
- The version is pinned with the `NDPID_REF` variable (tag or commit). After the build the built commit is printed together with a hint on how to pin it.
- If a ready binary already exists and runs (`-h` responds, no library loading errors), the build is skipped.
- Build packages are installed only when DPI is enabled. apt: `build-essential git cmake gettext flex bison libtool autoconf automake pkg-config libpcap-dev libjson-c-dev libnuma-dev libpcre2-dev libmaxminddb-dev librrd-dev`. dnf: `gcc gcc-c++ make git cmake gettext flex bison libtool autoconf automake pkgconf-pkg-config libpcap-devel json-c-devel numactl-devel pcre2-devel libmaxminddb-devel rrdtool-devel` (the dnf list is refined by testing). They are not removed automatically because they may have been installed earlier.
- The BPF filter flag is detected from the `nDPId -h` help output. If it is not found, a warning is printed and nDPId analyzes all traffic.
- Cloning and building run with a progress indicator (a spinner and the percentage from cmake output); the full log is shown only on error.
- The firewall is not changed until the build and installation have succeeded.
- Without nDPId the system works in static mode (`--no-dpi`); this is a normal situation. The listener is written in bash and does not require Python (section 6.4).

### Backups and self-check

`bb install` creates a timestamped backup (configs, units, `iptables-save`, `ipset save`, saved rule files) and finish with a verification: all sets exist; the DHT set is not empty; the chain has the flow and DHT rules; there is exactly one jump to the chain in `PREROUTING` and `OUTPUT`; no references to old objects remain; the required units are enabled. On success the backups are deleted (including leftovers from earlier failed attempts). On failure the backup is kept and the reason and its path are printed.

## 12. Files and systemd units

| Path | Purpose |
|---|---|
| `/usr/local/sbin/bb` | CLI |
| `/usr/share/bb/lang/` | message catalogs (`en.sh`, `ru.sh`) |
| `/etc/bb/bb.conf` | configuration |
| `/etc/bb/lists.d/` | descriptions of connected lists |
| `/etc/bb/allow.list`, `/etc/bb/manual.list` | source data for the allowlist and manual bans |
| `/etc/bb/notify.conf` | notification tokens and settings (root, 0600) |
| `/var/lib/bb/` | list cache, copy of dynamic flows, notification queue |
| `/var/backups/bb/` | rule backups (`iptables-save` for the chain or `nft list table`, ipset dump) |

Main `bb.conf` parameters: `lang` (`en` or `ru`, chosen at install), `backend` (detected at install), `install_backend`, `mode`, `ipv6`, `hook_priority` (-310, nft only), `list_maxelem` (1048576), `flow_ttl` (24h), `flow_maxelem` (262144), `flow_dedup` (600), `max_event_size` (1048576), `min_list_ratio` (50), `strip_private` (yes), `integrations` (auto), `guard_interval`, `confirm_timeout` (60), `flow_rate_limit`, `notify_*` (section 9, including `notify_lang`).

The configuration consists of `KEY='value'` lines, is read by a strict parser (no `source`), is written atomically (`.new` → `mv`) and has mode 0600.

| Unit | Purpose |
|---|---|
| `bb-sets.service` | iptables backend only: creates the sets from the cache before other firewall services load; `Before=netfilter-persistent.service iptables.service ip6tables.service ufw.service` |
| `bb-firewall.service` | applies the rules at boot after the other firewall services and saves the dynamic sets on stop; `After=nftables.service netfilter-persistent.service iptables.service ip6tables.service ufw.service bb-sets.service`, `Before=docker.service k3s.service`. The ordering is checked with `systemd-analyze verify` for cycles |
| `bb-update.timer` / `.service` | daily refresh of lists and DHT nodes |
| `bb-guard.timer` / `.service` | checks the rules and their position, reapplies them if they disappear, refreshes integration subnets |
| `bb-digest.timer` / `.service` | daily digest (if the `digest` event is enabled) |
| `bb-notify-failure@.service` | template unit invoked through `OnFailure=` for `bb` units; sends `service_failed` |
| `bb-ndpid.service` | nDPId with `-c` pointing at the listener socket, `Requires=bb-listener.socket` (only when DPI is enabled) |
| `bb-listener.socket` / `bb-listener@.service` | socket for nDPId (socket activation, `Accept=yes`) and a listener instance per connection (only when DPI is enabled) |

Logging: through journald, `bb` events carry the tag `bb` (`journalctl -t bb`), rule messages with the prefix `bb:` go to the kernel log. `bb log -f` merges both sources. A separate log file and rotation are not needed.

## 13. Security and protection against self-lockout

- blocking is enabled only after everything has been created and verified (syntax check, `bb doctor`);
- the allowlist always takes precedence over blocking;
- a backup of the rules before any change and an automatic rollback on an apply error;
- protection against an empty or sharply shrunk list;
- confirmation of `block` mode with a rollback timer (section 10);
- `bb uninstall` removes only `bb` objects (the jump and the `BB_FILTER` chain with the ipset sets, or the `inet bb` table) and its own units. The commands `iptables -F`, `iptables -t raw -F` and `nft flush ruleset` are never used anywhere, so that Docker, ufw, firewalld and kube-proxy are not affected;
- **locking against parallel runs:** all state-changing commands run under `flock /run/bb.lock` (waiting up to 30 seconds) so that timers and manual commands do not change the rules at the same time;
- **safe list downloads:** HTTPS only (including redirects), timeouts and retries, a file size limit, strict validation of every line; list contents are treated as untrusted and never executed; an optional `sha256=` in the list description;
- **privileges and isolation:** the listener does not run as root (user `bb`), nDPId runs as a separate user; units use `NoNewPrivileges=yes`, `ProtectSystem=strict`, `ProtectHome=yes`, `PrivateTmp=yes`, minimal capabilities (`CAP_NET_ADMIN` for firewall work, `CAP_NET_RAW` for capture in nDPId), `ReadWritePaths` only for `/var/lib/bb`;
- the nDPId socket is accessible to root only (`SocketMode=0600`);
- `bb uninstall` does not remove packages (they may have been installed earlier and used by the system); if the saved rule files referenced `bb` objects, they are re-saved without those references;
- **notification secrets:** tokens only in `/etc/bb/notify.conf` (0600), not in the journal and not in the process list (section 9);
- **SELinux** (dnf systems): operation is verified in enforcing mode, AVC denials are shown in `bb doctor`.

## 14. Load

Reference points (verify on your own machine):

- nDPId + listener: tens of MB of memory, low CPU load, grows with traffic;
- sets: hundreds of thousands of networks take a few to tens of megabytes, lookup is fast (ipset and nft hash tables);
- timers: seconds of work once a day (update) and milliseconds every few minutes (guard).

Levers: a port BPF filter for nDPId and disabling analysis on interfaces where it is not needed.

## 15. Limitations

- DPI blocking is reactive: the first packets of a flow pass before classification;
- encrypted and obfuscated BitTorrent (non-standard ports) is detected less reliably;
- tracker and DHT node lists cover only known addresses: a client with a peer cache, magnet links or PEX bypasses them;
- overly broad blocklists (CDNs, hosting) cause false positives, hence the monitor mode, the allowlist and private-range sanitizing;
- eBPF-based CNIs in k8s may bypass netfilter (section 8.2);
- the listener depends on the format and framing of nDPId events; they are re-verified by tests whenever the nDPId version changes;
- notifications depend on the availability of external services; Matrix is supported only in unencrypted rooms;
- in the iptables backend another tool may push the `BB_FILTER` jump out of the first position in raw; until `bb-guard` runs, protection may be incomplete;
- `nft flush ruleset` or a restart of `nftables.service` with `flush ruleset` removes protection for a while (until `bb-guard` runs);
- for more complete protection DNS-level blocking can be added, but that is a separate component and is not part of this project;
- outside apt/dnf, operation is not guaranteed;
- the interface is available in English and Russian only; other languages would need new catalogs.

## 16. Testing and acceptance criteria

Tools: `shellcheck` for scripts, `bats` for the CLI, syntax checks (`iptables-restore --test`, `nft -c`), a `curl` stub for testing notifications, a set of sample nDPId JSON events (including corrupted and malicious lines) for testing parsing in the listener, a catalog parity check (every key present in both `en.sh` and `ru.sh` with the same number and order of placeholders) and a lint that finds hard-coded user-visible strings outside the catalogs. Network namespaces (`ip netns`) are used to test blocking without real traffic.

Test matrix (containers or VMs): Debian 13 and 12, Ubuntu 24.04, Fedora, Rocky/Alma 9; the `iptables` backend (nf_tables and legacy) and the `nft` backend; scenarios with Docker, k3s, ufw (Debian/Ubuntu) and firewalld (RHEL/Fedora) installed; CLI smoke tests in both interface languages.

Acceptance criteria:

- on a system with iptables(nft) and without the `nftables` package, `bb install` selects the `iptables` backend, installs no extra packages and completes without manual steps (except nDPId);
- on a system without firewall utilities exactly one missing package is installed according to section 3;
- after a reboot the sets and rules are restored without network access and without errors;
- an IP from a list is unreachable in `block` mode and reachable in `monitor`;
- an address from the allowlist is always reachable;
- an interrupted download or an empty list does not change the existing set;
- `ufw reload`, `firewall-cmd --reload` and restarts of Docker and k3s do not break the `bb` rules, and `bb` does not break theirs;
- traffic from containers and pods to blocked addresses is dropped, while traffic between the containers and pods themselves passes;
- if the `BB_FILTER` jump is displaced from the first position or the rules are removed (`flush ruleset`), they are restored within `guard_interval` at most;
- on a clean system `bb` (including DPI) works without `python3`;
- if the rules were saved with `netfilter-persistent save` together with the `bb` chain, a reboot does not leave the host without rules;
- in the basic mode (no DPI, no Matrix, no `--json`) `jq` is not installed;
- the listener does not crash on corrupted, truncated or oversized messages and does not add invalid addresses or ports to the sets;
- on a mode change and when the protection fires, a message arrives in Telegram and Matrix; repeated identical events are suppressed;
- unavailability of Telegram or Matrix does not interfere with firewall operations, and messages are retried from the queue;
- the token is not visible in `ps`, in the journal or in the output of `bb status`;
- the language chosen at install time is stored and used everywhere: the whole interface, including `--help`, errors and notifications, is in that language with no mixing; `--json` output and exit codes are identical in both languages;
- with Russian selected on a non-UTF-8 terminal `bb` warns and offers English instead of printing garbled text;
- `bb uninstall` removes all `bb` objects and units, and the rest of the system's rules stay as they were.

## 17. Development order

1. **Core:** the abstraction layer and backend detection, sets and rules for both backends, `bb ban/unban/allow`, `bb mode`, `bb apply`, `flock` locking, OS detection (apt/dnf), and the message catalog infrastructure (`t`, `en.sh`, `ru.sh`, parity and lint checks) so that no string is ever hard-coded.
2. **Static lists:** download, validation, private-range sanitizing, atomic replacement, timer.
3. **DHT nodes** as a separate example of such a list.
4. **Installation and operation:** `bb install/uninstall`, installing missing packages, backup and automatic rollback, `bb-firewall.service`, `bb-guard.timer`, `block` mode confirmation, the install wizard (including language selection), self-check.
5. **Notifications:** `bb notify`, Telegram and Matrix via `curl`, the queue, flood protection, `OnFailure=`, the digest.
6. **Integrations:** Docker, k3s/k8s, ufw, firewalld, `bb integrate`, `bb doctor`.
7. **nDPId and the bash listener (with `jq`):** dynamic flows (optional), building nDPId and detecting the BPF flag, the listener socket unit, verifying the event format on a pinned version, unit hardening.
8. **Quality:** `--json`, `bb log`, tests and the distribution matrix.

The system becomes useful as early as step 2, without nDPId.
