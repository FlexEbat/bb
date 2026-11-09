# bb — a lightweight CLI blocker for BitTorrent, DHT and blocklists

**Version: v2** (2026-11-05)

**Status: under development.** Progress is tracked per slice in section 17; intentional differences between the code and this text are in section 18.

Changelog:

- v2 (2026-11-05): section 17 rewritten as slices with a status that is checked against the tests; new section 18, the deviation register; `bb uninstall` removes everything `bb` installed or configured, including the packages it added (sections 10, 11, 13, 16); verified facts about the nDPId event stream (sections 6.4, 11).
- v1: the first version of the specification.

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
| `internal4/6` | container and pod networks | exempt only when both the source and the destination are in it (see D-001) |
| `manual4/6` | addresses and networks, with timeout | manual bans |
| `list4/6` | addresses and networks | external lists and trackers |
| `dht4/6` | "address and port" pairs | DHT bootstrap nodes |
| `flow_src4/6`, `flow_dst4/6` | `hash:ip,port,ip` triples (`src,udp:sport,dst` and `dst,udp:dport,src`), with timeout (24 h) | dynamic flows from nDPId: source and destination are kept in two sets, each with both addresses (in the nft backend this is a single `flow` set holding the tuple "address, port, address, port") |

Check order:

1. loopback → pass;
2. `allow` (by source or destination) → pass (leave the `bb` chain); then `internal` (source and destination both in it) → pass (see D-001);
3. `manual` → drop;
4. `list` → drop;
5. `dht` (UDP) → drop, taking the port mode into account (section 11);
6. `flow` → drop: a packet is dropped if `(src, sport, dst)` is in `flow_src` and `(dst, dport, src)` is in `flow_dst`, or the other way round (the reply direction). `ipset` has no four-field type, so two triples stand in for the tuple "address, port, address, port": a packet is matched only when both addresses and both ports come from flows between the same two hosts. Two different flows between the same pair of hosts can still match together; flows between different hosts never do. An older set of the type `hash:ip,port` is replaced on `apply` (its flows are learned again).

Important: "pass" only means "do not apply `bb` blocking". The rules of ufw, firewalld, Docker and k8s keep working, and the `bb` allowlist does not cancel their denies.

**`monitor` mode:** instead of drop, a rule with a counter and rate-limited logging (`log prefix "bb: "`) is used; packets are not dropped.

**Atomic update and protection against "bad" lists:** a set is first filled in a temporary instance and then swapped in (ipset swap or an nft transaction). If the download fails, or the list is empty or has shrunk sharply (threshold `min_list_ratio`, 50% of the previous size by default), the old set is kept.

**After a reboot:** in the iptables backend, the `bb-sets.service` unit creates the sets from the cache in `/var/lib/bb` (without network access) before the other firewall services, then `bb-firewall.service` applies the rules (the ordering is explained in section 6.2). In the nft backend a single `bb-firewall.service` is enough.

### 6.2. The `iptables` + `ipset` backend

- ipset sets: `bb_allow4`, `bb_manual4`, `bb_list4` (`hash:net`), `bb_dht4`, `bb_flow_src4`, `bb_flow_dst4` (`hash:ip,port,ip`), with `family inet6` for IPv6; `maxelem` and `hashsize` are set explicitly (`list_maxelem`, 1,048,576 by default) because the default value (65,536) is too small for large lists;
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

- **Connection.** nDPId is started with `-c <path to a unix socket>` and connects by itself to the socket that the listener serves. The intermediate nDPIsrvd daemon is not needed. The interface is set with `-i`; the capture BPF filter uses a separate flag whose name differs between versions and is detected from the `nDPId -h` help output (section 11). Verified on nDPId 1.7: the capture-filter flag is `-B`; started as an unprivileged user nDPId tries to switch to `nobody` and exits unless `-u` and `-g` name its own user; and it opens one collector connection per reader thread (10 by default), so the unit sets `-o max-reader-threads=4` (see D-010).
- **Framing.** Each message is 5 decimal digits of length followed by JSON. The length is validated (limit `max_event_size`, 1 MiB by default); on an invalid header the connection is closed and nDPId reconnects. Verified on nDPId 1.7: the length counts the JSON's trailing newline, and a recorded stream is kept as the test fixture `tests/fixtures/ndpid-1.7.raw`.
- **Socket without `socat` or `nc`.** The `bb-listener.socket` unit (systemd socket activation: `ListenStream=/run/bb/ndpid.sock`, `Accept=yes`, `SocketUser=bb-ndpid` (see D-008), `SocketMode=0600`, `MaxConnections=8` (see D-010)) starts a `bb-listener@.service` instance for each connection, whose stdin and stdout are the socket itself (`StandardInput=socket`). Bash does not have to open the socket, the socket is available immediately, and nDPId can be started in any order.
- **Frame parsing.** `awk` under `LC_ALL=C` (so that lengths are bytes) checks each frame: five digits, a length from 1 to `max_event_size`, and the payload with exactly that length including its trailing newline (a frame that spreads over several lines is joined with spaces). Any violation ends the connection and is logged as `listener_frame_error` with the reason `header`, `length` or `truncated`. The clean JSON objects go to a single long-lived `jq --unbuffered -c` process (the pipeline "frame parsing → `jq` → apply"). The unit sets `MemoryMax`, because a single line without a newline is read whole.
- **`jq` filter.** Events whose `flow_event_name` is `detected` or `detection-update` are taken. The `guessed` event, where the protocol was determined by port, is ignored as unreliable. Conditions: the `ndpi.proto` field contains `bittorrent` (case-insensitive), `l4_proto` is `tcp` or `udp`, `src_ip` and `dst_ip` are of the same family, ports are 1–65535. The output is compact lines "family, source, destination" with elements of the form `address,protocol:port`.
- **Validation twice:** in `jq` (IPv4/IPv6 patterns, port range) and once more in bash before applying. Other strings from events (SNI, host names, etc.) are untrusted and are never substituted into commands.
- **Batched application:** accumulated additions are applied every few seconds in a single call (`ipset restore -exist` with the `flow_ttl` timeout, or a single `nft -f -` transaction).
- **Deduplication:** an associative array "flow → time until which repeated events are ignored" (`flow_dedup`, 600 s by default). After the window the entry is refreshed and the TTL extended. The array size is capped (100,000 entries); when full it is cleared, so memory does not grow.
- **Protection:** addresses from the allowlist and private ranges never enter `flow`; the number of new entries per minute is limited (`flow_rate_limit`); when exceeded, the listener pauses and sends a `rate_limit` notification.
- **Resilience:** corrupted, truncated and oversized messages are skipped or close the connection (see above), nDPId reconnects, and `bb-listener.socket` stays active.
- **Privileges.** The listener runs as the unprivileged user `bb` with only `CAP_NET_ADMIN`. It cannot read `/etc/bb`: it gets a copy of the few settings it needs in `/var/lib/bb/listener.conf`, writes only to `/var/lib/bb/listener/`, reads the allowlist from the live kernel set, and leaves `rate_limit` notes that the guard turns into notifications (see D-009).
- **Why `jq`:** it is a real parser from the standard repositories, one small package, installed only when needed. A home-grown awk parser (hard to maintain, mawk vs gawk differences) and a separate Go or C binary (building and distributing for different architectures contradicts the "bash and repository packages" goal) were considered and rejected.

## 7. Lists

**Static** (files and URLs):

- DHT bootstrap nodes, resolved by a timer. Each node is given as a "name:port" pair (for example `router.bittorrent.com:6881` and `dht.libtorrent.org:25401`) because node ports differ. Private and special-purpose addresses (including IPv4-mapped IPv6) are dropped from the result and duplicates are removed;
- public trackers (for example ngosang/trackerslist, IPs or hosts);
- P2P activity blocklists and any custom network lists;
- the manual list (`bb ban`).

**Dynamic** (from nDPId): flows detected as BitTorrent, in both directions, TTL 24 h.

**Allowlist**: gateway, DNS, administrator addresses. It is checked before any blocking. At install time the default gateway, the DNS servers from the system configuration and the IP of the current SSH session are added automatically. Integrations (section 8) add container and cluster subnets.

List file format: one entry per line (IP or CIDR), lines starting with `#` and empty lines are ignored, hosts are resolved on update. Names are resolved 16 at a time (5 seconds at most for each, at most `resolve_max` names per list) and the whole resolution is cut off after `resolve_budget` seconds (120 by default); names that are not resolved by then are skipped and a warning is printed.

List sanitizing: private and special-purpose ranges (RFC 1918, 100.64.0.0/10, loopback, link-local, ULA `fc00::/7`) are removed from external lists unless `strip_private=no`. This keeps container and cluster networks from being blocked.

Entries broader than /8 (IPv4) or /16 (IPv6) are rejected, so that one bad line cannot block everything (see D-005).

### Failure handling and locking

- The allowlist, the internal networks and the manual bans are critical: if one of those sets cannot be loaded, `apply` rolls back. The blocklists and the DHT nodes are not: if they cannot be loaded (for example a list larger than `list_maxelem` on the `ipset` backend), the rules are still applied without them, the failure is reported (`list_update_failed ... reason=load`) and `guard` can still restore the protection.
- On the `ipset` backend a list with more entries than `list_maxelem` is rejected at update time (reason `size`) and the old data is kept.
- `bb list update` downloads, checks and normalizes without the lock. Only the safety checks against the stored state, the cache and the set reload run under the lock, so `guard` and `apply` never wait for the network. A busy lock is not a failure of `guard`: it logs `guard_skipped reason=lock` and runs again at the next interval. `bb mode block --confirm` releases the lock while it waits for the answer.
- `bb-firewall.service` is ordered `Before=network-pre.target` (after the services that load other rules), so that the rules are in place before the network comes up.

## 8. Integrations

General principle: `bb` does not modify the rules or configuration of Docker, k8s, ufw and firewalld. It (1) works in its own objects (the `BB_FILTER` chain in raw or the `inet bb` table), (2) adds container and pod networks to `internal` and node addresses to `allow` (see D-001), (3) checks compatibility with `bb doctor`. Management: `bb integrate auto|docker|k8s|ufw|firewalld|status`. The default mode is `auto` (detection at install time and refresh by the `bb-guard` timer).

### 8.1. Docker

- Docker (iptables) creates its own chains (`DOCKER`, `DOCKER-USER`, NAT) and puts some rules in raw. `bb` rules run before DNAT, so published ports and container traffic are blocked by the original address. Rules in `DOCKER-USER` are not used.
- Docker network subnets (`docker0`, `br-*`) are added to `internal` automatically (see D-001), detected from interfaces and, if available, via `docker network inspect`. The list is refreshed by a timer.
- On start and restart Docker may insert its own rules at the top of raw: this is covered by the position check (section 6.2). Restarting Docker does not remove the `bb` sets and chain.
- `bb-firewall.service` starts before `docker.service` (ordering only, no hard dependency).

### 8.2. k3s / k8s

- `bb` is installed on each node separately. Centralized cluster management is out of scope.
- kube-proxy modes (iptables, ipvs, nftables) do not matter: they have their own chains and tables.
- Added to `internal` (see D-001): pod CIDR and service CIDR. Added to `allow`: node IPs. Detection is automatic where possible: for k3s from `/etc/rancher/k3s/config.yaml` and `config.yaml.d/` (defaults 10.42.0.0/16 and 10.43.0.0/16), for kubeadm from the `kube-controller-manager` manifests, and node addresses if `kubectl` is available. Whatever cannot be detected is set manually (`k8s_pod_cidr`, `k8s_service_cidr`, `bb allow`).
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
bb log [-f] [-n N]               event log (journal tag bb and kernel messages "bb:")
bb mode monitor|block [--confirm 60]
bb uninstall [--yes] [--keep-packages]   remove everything bb installed or configured
```

Additions to this list are recorded in D-004 (see D-004).

General rules: commands that change the system require root; exit code 0 on success, non-zero on error with a message on stderr; every subcommand has `--help`; all state-changing commands take a lock (section 13); every command accepts the global `--lang en|ru` flag. `--json` mode is built with `jq`; if it is missing, an installation hint is printed.

**`bb mode`**: `monitor` mode writes to the log and keeps counters but does not drop (the default after installation). With `bb mode block --confirm N` the mode rolls back to `monitor` if the administrator does not confirm it within N seconds (60 by default, rollback via a transient `systemd-run` timer). An unconfirmed `block` is also reverted after a reboot (see D-006).

**`bb uninstall`** removes everything `bb` installed or configured, and nothing else: its systemd units and timers, its firewall objects (the `BB_FILTER` chain and ipset sets, or the `inet bb` table), the configuration, state and backups (`/etc/bb`, `/var/lib/bb`, `/var/backups/bb`), the `bb` and `bb-ndpid` users, the binaries (`bb`, `bb-ndpid`), the language catalogs, the lock, and the packages that `bb install` added. Packages are tracked in `/var/lib/bb/manifest` as the difference between the installed packages before and after each installation (dependencies included, including the build packages for nDPId); a package is kept, and reported, if removing it would also remove other software. `--keep-packages` leaves all packages alone. Saved rule files that referenced `bb` objects are re-saved without them. On a terminal the command asks for confirmation; without one it needs `--yes`.

**`bb doctor`** checks: the selected backend and the presence of the required utilities and kernel modules; the iptables variant (nf_tables or legacy); the presence of the `bb` chain or table and the jump position; the state of units and timers; a non-empty allowlist (gateway, DNS, SSH IP); whether `nftables.service` is enabled and whether its configuration contains `flush ruleset`; the status of Docker, k3s/k8s, ufw, firewalld; on dnf systems, SELinux and recent AVC denials for `bb`; the permissions of `/etc/bb/notify.conf` and the notification queue size; the language catalogs (both present, selected language available).

### `--json` output

`bb status --json` prints one document: `version`, `backend` (`iptables` or `nft`), `iptables_variant` (`nf_tables`, `legacy`, `unknown`, or `null` for `nft`), `mode`, `lang`, `rules` (`active` or `inactive`), `sets` (a list of `{name, entries}`, `entries` is a number or `null` when the set cannot be read) and `counters` (a list of `{category, packets, bytes}`). When the rules are not active `sets` and `counters` are empty.

`bb doctor --json` prints one document: `version`, `ok`, `fail`, `warn` and `checks`, a list of `{level, id, args}` where `level` is `ok`, `warn` or `fail`, `id` is the catalog key of the check without its `doc_` prefix (for example `backend_ok`, `rules_fail`) and `args` are the raw values the text message would show. There is no message text, so the document is identical in both languages. The exit code is the same as without `--json`.

Both documents are built with `jq`. Without `jq` the command prints how to install it and exits non-zero, before doing anything else.

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

- nDPId is not in the standard repositories, so it is built from source: `git clone --depth 1 --branch $NDPID_REF` and `git submodule update --init --depth 1 libnDPI` (see D-007), `cmake -DBUILD_NDPI=ON -DBUILD_EXAMPLES=OFF`, `make -j"$(nproc)"`. The binary is copied to `/usr/local/bin/bb-ndpid` and the build directory is removed.
- The version is pinned with the `NDPID_REF` variable (tag or commit). After the build the built commit is printed together with a hint on how to pin it.
- If a ready binary already exists and runs (`-h` responds, no library loading errors), the build is skipped.
- Build packages are installed only when DPI is enabled. apt: `build-essential git cmake gettext flex bison libtool autoconf automake pkg-config libpcap-dev libjson-c-dev libnuma-dev libpcre2-dev libmaxminddb-dev librrd-dev`. dnf: `gcc gcc-c++ make git cmake gettext flex bison libtool autoconf automake pkgconf-pkg-config libpcap-devel json-c-devel numactl-devel pcre2-devel libmaxminddb-devel rrdtool-devel` (the dnf list is refined by testing). They are recorded in the manifest (section 10), so `bb uninstall` removes the ones that `bb` itself installed, unless something else depends on them.
- The BPF filter flag is detected from the `nDPId -h` help output. If it is not found, a warning is printed and nDPId analyzes all traffic.
- Cloning and building run with a progress indicator (a spinner and the percentage from cmake output); the full log is shown only on error.
- The firewall is not changed until the build and installation have succeeded.
- Without nDPId the system works in static mode (`--no-dpi`); this is a normal situation. The listener is written in bash and does not require Python (section 6.4).

### Backups and self-check

`bb install` creates a timestamped backup (configs, units, `iptables-save`, `ipset save`, saved rule files) and finish with a verification: all sets exist; the DHT set is not empty (an empty set is only a warning, see D-002); the chain has the flow and DHT rules; there is exactly one jump to the chain in `PREROUTING` and `OUTPUT`; no references to old objects remain; the required units are enabled. On success the backups are deleted (including leftovers from earlier failed attempts). On failure the backup is kept and the reason and its path are printed.

## 12. Files and systemd units

| Path | Purpose |
|---|---|
| `/usr/local/sbin/bb` | CLI |
| `/usr/share/bb/lang/` | message catalogs (`en.sh`, `ru.sh`) |
| `/etc/bb/bb.conf` | configuration |
| `/etc/bb/lists.d/` | descriptions of connected lists |
| `/etc/bb/allow.list`, `/etc/bb/manual.list` | source data for the allowlist and manual bans |
| `/etc/bb/notify.conf` | notification secrets: tokens, chat, homeserver, room (root, 0600); the other `notify_*` settings are in `bb.conf` (see D-003) |
| `/var/lib/bb/` | list cache, copy of dynamic flows, notification queue, integration networks, `manifest` (what `bb` installed, for `bb uninstall`) |
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
- the firewall objects are `bb`'s own (the jump and the `BB_FILTER` chain with the ipset sets, or the `inet bb` table). The commands `iptables -F`, `iptables -t raw -F` and `nft flush ruleset` are never used anywhere, so that Docker, ufw, firewalld and kube-proxy are not affected; `bb uninstall` removes only those objects;
- **locking against parallel runs:** all state-changing commands run under `flock /run/bb.lock` (waiting up to 30 seconds) so that timers and manual commands do not change the rules at the same time;
- **safe list downloads:** HTTPS only (including redirects), timeouts and retries, a file size limit, strict validation of every line; list contents are treated as untrusted and never executed; an optional `sha256=` in the list description;
- **privileges and isolation:** the listener does not run as root (user `bb`), nDPId runs as a separate user; units use `NoNewPrivileges=yes`, `ProtectSystem=strict`, `ProtectHome=yes`, `PrivateTmp=yes`, minimal capabilities (`CAP_NET_ADMIN` for firewall work, `CAP_NET_RAW` for capture in nDPId), `ReadWritePaths` only for `/var/lib/bb`;
- the nDPId socket is accessible only to the nDPId user and root (`SocketUser=bb-ndpid`, `SocketMode=0600`, see D-008);
- `bb uninstall` removes everything `bb` installed or configured (section 10), including the packages it added unless other software depends on them; if the saved rule files referenced `bb` objects, they are re-saved without those references;
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
- `bb uninstall` removes everything `bb` installed or configured (units, rules, sets, configuration, state, users, binaries and the packages it added), and the rest of the system's rules stay as they were.

## 17. Stages and slices

The work is split into vertical slices, done in order. A slice is closed when every criterion of it is `[x]`.

**Format.** `### Slice <label>: title`, with **Files**, **What it does**, **Acceptance criteria** (a numbered list, the criterion ID is `S<label>.<number>`), **Tests** and **Not to do**.

**Markers.** `[x]` done: implemented and verified by the tests it cites, as `(tests/<file>: <part of the test name>)`, or marked `(manual)`. `[~]` implemented, but a part could not be verified yet (the line says what). `[ ]` not done.

**Rules.**

- The cited tests are checked by `tests/check-spec.sh` (also part of `make test`): the file must exist, the test name part must be in it, a `[x]` criterion without a test fails, and the status table below must equal the one computed from the criteria. The table is never edited by hand: run `tests/check-spec.sh --table`.
- Where the implementation deliberately differs from this file, the difference is recorded in the deviation register (section 18) and not left implicit.
- Stages: 1. core (S1); 2. lists (S2, S3); 3. installation, notifications, integrations (S4, S5, S6); 4. dynamic layer (S7); 5. machine-readable output and logs (S8); 6. test matrix (S9); 7. documentation and release (S10).

| Slice | Title | Status | Criteria |
|---|---|---|---|
| S1 | Core | partial | 15/17 |
| S2 | Static lists | partial | 8/9 |
| S3 | DHT nodes | done | 4/4 |
| S4 | Installation and operation | partial | 15/16 |
| S5 | Notifications | partial | 11/12 |
| S6 | Integrations and diagnostics | partial | 8/9 |
| S7 | Dynamic layer (nDPId and the listener) | partial | 17/20 |
| S8 | Machine-readable output and logs | partial | 2/3 |
| S9 | Test matrix and CI | partial | 1/7 |
| S10 | Documentation and release | partial | 3/4 |

---

### Slice 1: Core

**Files:** `src/bb`, `lang/en.sh`, `lang/ru.sh`, `src/net.awk`, `tests/backend.bats`, `tests/cli.bats`.

**What it does:** backend detection and the abstraction layer, sets and rules for both backends, `bb ban/unban/allow`, `bb mode`, `bb apply`, `bb guard`, `flock` locking, the message catalogs.

**Acceptance criteria:**

1. [x] **S1.1** The backend follows section 3 and only missing packages are installed. (tests/install.bats: packages: nft path installs exactly the missing logical packages) (tests/install.bats: backend: iptables without the nftables package is used as is)
2. [x] **S1.2** A manual ban passes in `monitor` mode (counted), is dropped in `block` mode, and `unban` restores traffic. (tests/backend.bats: manual ban: monitor passes, block drops, unban restores)
3. [x] **S1.3** The allowlist always beats a broader ban. (tests/backend.bats: allowlist beats a broader ban)
4. [x] **S1.4** Both directions are blocked (traffic to and from a banned address) and loopback is never touched. (tests/backend.bats: inbound traffic from a banned peer is dropped) (tests/backend.bats: loopback is never touched)
5. [x] **S1.5** A ban TTL expires on its own and survives a rebuild of the rules. (tests/backend.bats: ban TTL expires and the file is pruned) (tests/backend.bats: ban with TTL survives a rebuild)
6. [x] **S1.6** Entries are validated and canonicalized (IPv4/IPv6, host bits cleared); invalid and too broad entries are rejected (see D-005). (tests/cli.bats: norm: networks are canonicalized) (tests/cli.bats: norm: invalid and too-broad entries are rejected)
7. [x] **S1.7** `bb guard` restores wiped rules and a displaced jump, and repeated `apply` never duplicates it. (tests/backend.bats: guard restores wiped rules) (tests/backend.bats: guard puts a displaced jump back in first place)
8. [x] **S1.8** A failing apply leaves the running protection in place. (tests/backend.bats: a failing apply keeps the running protection)
9. [x] **S1.9** Foreign rules coexist: a foreign `ACCEPT` at the top of `raw` cannot shield blocked traffic, and removal touches only `bb` objects. (tests/backend.bats: foreign ACCEPT at the top of raw cannot shield blocked traffic) (tests/backend.bats: removal touches only bb objects)
10. [x] **S1.10** State-changing commands take a lock: a second command waits and then fails with a message. (tests/cli.bats: locking: a second state-changing command waits for the lock)
11. [x] **S1.11** The configuration is read by a strict parser that never executes it, and written atomically with mode 0600. (tests/cli.bats: config: strict parser ignores junk lines) (tests/cli.bats: config file is mode 0600 and written atomically)
12. [x] **S1.12** `bb mode block --confirm` arms a rollback timer, refuses without `systemd-run`, and an unconfirmed block is reverted after a reboot (see D-006). (tests/backend.bats: block --confirm arms a rollback timer) (tests/backend.bats: block --confirm without systemd-run refuses) (tests/install.bats: an unconfirmed block mode is reverted by apply/guard)
13. [x] **S1.13** The language is chosen by flag, `BB_LANG`, `bb.conf`, then English; Russian falls back to English on a non-UTF-8 locale; catalogs have the same keys and placeholders and no string is hard-coded. (tests/cli.bats: language: precedence flag > BB_LANG > bb.conf > en) (tests/cli.bats: language: Russian on a non-UTF-8 locale) (tests/lint.sh: placeholder mismatch)
14. [x] **S1.14** In the `nft` backend a changed `hook_priority` recreates the base chains. (tests/backend.bats: changed hook_priority recreates the base chains)
15. [x] **S1.15** No interpreter (Python, Perl, Ruby, Node) is used by the product. (tests/lint.sh: no interpreters)
16. [~] **S1.16** IPv6 blocking works. The sets and rules are created and loaded, but the traffic test skips itself in an environment without IPv6. (tests/backend.bats: ipv6 ban)
17. [~] **S1.17** Both `iptables` variants work. Only `nf_tables` has been run; the `legacy` variant is covered by slice 9.

**Tests:** `tests/backend.bats` (real traffic between two network namespaces on both backends), `tests/cli.bats`, `tests/lint.sh`.

**Not to do:** a web panel, a database, any heavy IDS.

---

### Slice 2: Static lists

**Files:** `src/bb`, `src/net.awk`, `tests/cli.bats`, `tests/backend.bats`.

**What it does:** `bb list add|update|rm`, download, validation, private-range sanitizing, atomic replacement, the daily timer.

**Acceptance criteria:**

1. [x] **S2.1** Only HTTPS sources are accepted, including redirects, with timeouts and a size limit. (tests/cli.bats: lists: only https sources, valid names, sha256 format) (tests/cli.bats: lists: https download goes through curl with https-only protocol flags)
2. [x] **S2.2** List content is untrusted: every line is validated, private and special ranges are dropped, nothing is executed. (tests/cli.bats: lists: strict sanitizing of untrusted content) (tests/cli.bats: lists: strip_private=no keeps private ranges)
3. [x] **S2.3** An empty, sharply shrunk or vanished source keeps the old set. (tests/backend.bats: list: empty, shrunk and vanished sources keep the old set)
4. [x] **S2.4** An oversized list is rejected, and a `sha256=` mismatch keeps the old data. (tests/cli.bats: lists: size limit rejects oversized lists) (tests/cli.bats: lists: sha256 mismatch keeps the old data and fails)
5. [x] **S2.5** Host names in a list are resolved, private resolutions and junk are dropped. (tests/cli.bats: lists: hosts are resolved, private resolutions dropped, junk hosts ignored)
6. [x] **S2.6** An IP from a list is unreachable in `block` mode and reachable in `monitor` mode. (tests/backend.bats: list: monitor passes, block drops, removal restores)
7. [x] **S2.7** Overlapping and duplicate networks from several lists load on both backends. (tests/backend.bats: list: overlapping and duplicate networks load)
8. [x] **S2.8** The daily update timer is installed and its ordering is valid. (tests/install.bats: units: syntax and ordering verified by systemd-analyze)
9. [~] **S2.9** The `wget` download path works. Only the `curl` path is exercised by tests.

**Tests:** `tests/cli.bats`, `tests/backend.bats`.

**Not to do:** list formats other than one entry per line (IP, CIDR, host name or tracker URL).

---

### Slice 3: DHT nodes

**Files:** `src/bb`, `tests/backend.bats`.

**What it does:** bootstrap nodes (`name:port`) resolved by the update timer into the `dht` sets, blocked by the port mode.

**Acceptance criteria:**

1. [x] **S3.1** Node names are resolved, private and unresolvable ones are dropped. (tests/backend.bats: dht: host names resolved, private and unresolvable dropped)
2. [x] **S3.2** A resolution that returns nothing keeps the previous set. (tests/backend.bats: dht: empty resolution keeps the old set)
3. [x] **S3.3** The port modes `all`, `only` and `except` block as specified on both backends. (tests/backend.bats: dht: all / except / only port modes)
4. [x] **S3.4** A default node list is created at install. (tests/install.bats: install (nft): config, allowlist, rules in monitor mode, units, no leftovers)

**Tests:** `tests/backend.bats`.

**Not to do:** resolving through anything but the system resolver.

---

### Slice 4: Installation and operation

**Files:** `src/bb`, `tests/install.bats`.

**What it does:** `bb install` (wizard, platform check, package plan, backup, allowlist auto-fill, units, self-check), `bb uninstall`, the units and timers, `block` confirmation after a reboot.

**Acceptance criteria:**

1. [x] **S4.1** Arguments are validated before anything changes. (tests/install.bats: arguments are validated before anything changes)
2. [x] **S4.2** An unsupported distribution stops the install unless `--force`. (tests/install.bats: platform: unknown distribution stops unless --force)
3. [x] **S4.3** A failing package installation changes nothing, and what was installed is recorded for the uninstall. (tests/install.bats: packages: a failing install changes nothing) (tests/install.bats: a failed package installation is still recorded so that uninstall can clean it up)
4. [x] **S4.4** A backup is made before any change, kept (with its path) when the self-check fails, and dropped on success. (tests/install.bats: failed self-check keeps the backup and says where it is) (tests/install.bats: install (nft): config, allowlist, rules in monitor mode, units, no leftovers)
5. [x] **S4.5** The allowlist is filled with the gateway, DNS servers and the current SSH client. (tests/install.bats: install (nft): config, allowlist, rules in monitor mode, units, no leftovers)
6. [x] **S4.6** Units carry the specified ordering and are valid for `systemd-analyze`; the sets unit exists for the `iptables` backend only. (tests/install.bats: units: syntax and ordering verified by systemd-analyze) (tests/install.bats: install (iptables): sets service is created and wired in)
7. [x] **S4.7** Installing again keeps bans and the allowlist and creates no duplicates. (tests/install.bats: install is repeatable: keeps bans and allowlist, no duplicates)
8. [x] **S4.8** After a boot the sets come from the cache without network access, before any rule. (tests/install.bats: boot path: __sets-restore recreates sets and bans without any rules)
9. [x] **S4.9** An empty DHT set at the end of the install is a warning, not a failure (see D-002). (tests/install.bats: install without working DNS still completes)
10. [x] **S4.10** The port-mode flags reach the configuration and the rules. (tests/install.bats: port mode flags end up in the config and in the rules)
11. [x] **S4.11** The installer output is fully localized. (tests/install.bats: install output is fully Russian with --lang ru)
12. [x] **S4.12** `bb uninstall` removes everything `bb` installed or configured: units, rules and sets, configuration, state, backups, binaries and the lock, and touches no other firewall object. (tests/install.bats: uninstall removes everything of bb, only bb objects of the firewall, and cleans saved rule files)
13. [x] **S4.13** `bb uninstall` removes the packages `bb` installed, dependencies included, and keeps any package whose removal would also remove other software. (tests/install.bats: uninstall (apt) removes the packages bb installed, dependencies included, and nothing else) (tests/install.bats: uninstall keeps a package other software depends on, and says so) (tests/install.bats: uninstall (dnf) keeps packages that other installed software requires)
14. [x] **S4.14** Saved rule files that referenced `bb` objects are re-saved without them. (tests/install.bats: uninstall removes everything of bb, only bb objects of the firewall, and cleans saved rule files)
15. [x] **S4.15** `bb uninstall` asks for confirmation on a terminal and needs `--yes` otherwise. (tests/install.bats: uninstall needs --yes without a terminal)
16. [~] **S4.16** The units start under a real systemd. They are only checked with `systemd-analyze` and stubs here; covered by slice 9.

**Tests:** `tests/install.bats`.

**Not to do:** touching the rules of other tools, flushing a ruleset.

---

### Slice 5: Notifications

**Files:** `src/bb`, `tests/notify.bats`.

**What it does:** `bb notify`, Telegram and Matrix through `curl`, the queue, flood protection, `OnFailure=`, the digest.

**Acceptance criteria:**

1. [x] **S5.1** Setup is verified with a test message and saves nothing when it fails; bad input is rejected before any network call. (tests/notify.bats: setup rejects bad input before touching the network)
2. [x] **S5.2** Secrets live in `notify.conf` (root, 0600) and never appear in the process list, output, status or journal (see D-003). (tests/notify.bats: secrets never appear in the process list, output, status or journal) (tests/notify.bats: telegram setup: verified with a test message, secrets only in notify.conf)
3. [x] **S5.3** Values are quoted for the curl configuration and event data cannot inject into messages. (tests/notify.bats: curl config quoting: quotes, backslashes and newlines cannot break out of a value) (tests/notify.bats: untrusted event data cannot inject into messages or curl config)
4. [x] **S5.4** Matrix messages use a bearer header, an encoded room and valid JSON. (tests/notify.bats: matrix: PUT with bearer header, room encoded, JSON built by jq) (tests/notify.bats: matrix messages are valid JSON even for multi-line bodies)
5. [x] **S5.5** Only the enabled events are sent; manual changes never carry the address. (tests/notify.bats: events: only the enabled ones are sent; manual changes never carry the address)
6. [x] **S5.6** Identical events are suppressed for `notify_dedup`, and an hourly limit sends one summary message. (tests/notify.bats: flood protection: identical events are suppressed for notify_dedup) (tests/notify.bats: flood protection: global hourly limit, one summary message afterwards)
7. [x] **S5.7** Undelivered messages are queued, retried, expired and bounded, with per-channel progress. (tests/notify.bats: queue: undelivered messages are kept and retried) (tests/notify.bats: queue: expired messages are discarded, not sent) (tests/notify.bats: queue: bounded, the oldest messages are dropped first)
8. [x] **S5.8** Delivery runs in the background: a dead network never delays or fails a firewall command. (tests/notify.bats: delivery is in the background)
9. [x] **S5.9** The notification endpoints stay in the allowlist. (tests/notify.bats: notification endpoints are allowlisted)
10. [x] **S5.10** The guard retries the queue; a failed `bb` unit is reported through `OnFailure=`; the digest holds no addresses. (tests/notify.bats: guard retries the queue and reports restored rules) (tests/notify.bats: units: failure hook and digest are wired) (tests/notify.bats: daily digest: modes, sets, packets since last time, list sizes; no addresses)
11. [x] **S5.11** Notification texts follow `notify_lang`, event identifiers stay English; a proxy can be set. (tests/notify.bats: mode change notification, in English and in Russian) (tests/notify.bats: proxy is passed in the curl config and validated)
12. [~] **S5.12** The live Telegram and Matrix APIs accept the requests. Only a stubbed `curl` is used here.

**Tests:** `tests/notify.bats`.

**Not to do:** end-to-end encrypted Matrix rooms, other channels.

---

### Slice 6: Integrations and diagnostics

**Files:** `src/bb`, `tests/integrations.bats`.

**What it does:** `bb integrate`, the `internal` sets (see D-001), `bb doctor`.

**Acceptance criteria:**

1. [x] **S6.1** Docker networks come from `docker0`, `br-*` and `docker network inspect`, IPv6 included. (tests/integrations.bats: docker0 and br-* networks go to the internal set) (tests/integrations.bats: docker network inspect adds subnets, IPv6 included)
2. [x] **S6.2** k3s (every configuration form and its defaults), kubeadm manifests and manual settings are understood. (tests/integrations.bats: k3s config: inline, quoted, dual-stack, list form and config.d are all understood) (tests/integrations.bats: k3s defaults, kubeadm manifests and manual settings)
3. [x] **S6.3** Containers and pods reach each other but not blocked addresses (see D-001). (tests/integrations.bats: containers/pods talk to each other, but not to blocked addresses)
4. [x] **S6.4** Node addresses join the allowlist and beat a ban. (tests/integrations.bats: node addresses (kubectl) join the allowlist and beat a ban)
5. [x] **S6.5** The guard picks up new networks, a reboot loads them from the cache, and a change is announced once. (tests/integrations.bats: guard picks up new Docker networks) (tests/integrations.bats: after a reboot the internal networks load from the cache) (tests/integrations.bats: integration changes are announced once)
6. [x] **S6.6** `bb integrate` selects, disables and reports integrations (see D-004); ufw and firewalld are reported and never modified. (tests/integrations.bats: bb integrate: selection, none, auto, errors and status) (tests/integrations.bats: ufw and firewalld are reported, never modified)
7. [x] **S6.7** `bb doctor` reports each area and exits 1 on a failure. (tests/integrations.bats: doctor: healthy system exits 0 and reports each area) (tests/integrations.bats: doctor: wiped rules are a FAIL)
8. [x] **S6.8** `bb doctor` calls out `flush ruleset` in `nftables.service`, other firewall tools, SELinux denials, saved rule files, file permissions and the queue. (tests/integrations.bats: doctor: nftables.service with 'flush ruleset' is called out) (tests/integrations.bats: doctor: other firewall tools and integrations are listed) (tests/integrations.bats: doctor: saved rule files that mention bb objects) (tests/integrations.bats: doctor: notify.conf permissions, queue size and no secrets in the output)
9. [~] **S6.9** Docker, k3s, ufw and firewalld behave as modelled. They are stubbed here; restart and reload scenarios are covered by slice 9.

**Tests:** `tests/integrations.bats`.

**Not to do:** changing the rules or configuration of Docker, k8s, ufw or firewalld; centralized cluster management.

---

### Slice 7: Dynamic layer (nDPId and the listener)

**Files:** `src/bb`, `tests/dpi.bats`, `tests/dpi_install.bats`, `tests/e2e.bats`, `tests/fixtures/`.

**What it does:** builds nDPId from a pinned reference, the listener (bash and `jq`) behind a socket unit, dynamic flows in `flow` sets that survive a restart, `bb show flows`.

**Acceptance criteria:**

1. [x] **S7.1** nDPId is built from a pinned reference (a tag or a commit) with only the `libnDPI` submodule initialised (see D-007), installed as `bb-ndpid`, not built again when it is there, and a failed build changes nothing and says how to go on. (tests/dpi_install.bats: the build clones the pinned tag and initialises only libnDPI) (tests/dpi_install.bats: an installed nDPId is not built again) (tests/dpi_install.bats: a failed build leaves the firewall, the configuration and the users untouched)
2. [x] **S7.2** The capture-filter option is read from the help of the installed build, the port mode produces the filter, and a build without that option stops the install before anything changes. (tests/dpi_install.bats: the port mode becomes the capture filter, using the option found in the help of the build) (tests/dpi_install.bats: a build without a capture-filter option stops the install before anything changes)
3. [x] **S7.3** The listener understands the stream of the real nDPId 1.7, whose frame length includes the trailing newline. (tests/dpi.bats: the real nDPId 1.7 stream yields the BitTorrent flows)
4. [x] **S7.4** Invalid, truncated and oversized frames end the connection safely, and corrupt JSON lines are skipped. (tests/dpi.bats: invalid, truncated and oversized frames end the connection safely) (tests/dpi.bats: corrupt JSON lines are skipped and the stream goes on)
5. [x] **S7.5** Only `detected` and `detection-update` events of BitTorrent become flows. (tests/dpi.bats: only detected and detection-update BitTorrent events become flows)
6. [x] **S7.6** Hostile or malformed fields never reach a command. (tests/dpi.bats: hostile or malformed fields never reach a command)
7. [x] **S7.7** Private, special and allowlisted addresses never enter `flow`, on the source side and on the destination side. (tests/dpi.bats: private, special and allowlisted addresses never enter flow)
8. [x] **S7.8** Repeated events are deduplicated. (tests/dpi.bats: repeated events are deduplicated)
9. [~] **S7.9** The deduplication memory is bounded (cleared at 100,000 entries). The cap is in the code but has not been stress-tested.
10. [x] **S7.10** Exceeding the rate limit pauses the listener, and the guard turns its note into a `rate_limit` event; anything but the exact note format is ignored (see D-009). (tests/dpi.bats: exceeding the rate limit pauses the listener and raises rate_limit once)
11. [x] **S7.11** Flows block by the full tuple, not by host, on both backends. (tests/backend.bats: flow: blocks by full tuple, not by host)
12. [x] **S7.12** The listener runs as an unprivileged user with `CAP_NET_ADMIN` and nothing else, nDPId runs as its own user, and the socket belongs to that user (see D-008, D-010, D-009). (tests/dpi_install.bats: the listener runs as an unprivileged user with CAP_NET_ADMIN and nothing else) (tests/dpi_install.bats: units: the socket belongs to the nDPId user)
13. [x] **S7.13** Dynamic flows survive a restart with what is left of their TTL, and expired ones are not restored. (tests/dpi.bats: dynamic flows survive a restart with what is left of their TTL) (tests/dpi.bats: a flow whose TTL ran out while the host was down is not restored)
14. [x] **S7.14** `bb show flows` lists the flows, says when there are none, and is localized. (tests/dpi.bats: bb show flows lists the flows, says when there are none, and is localized)
15. [x] **S7.15** A live capture through the real nDPId ends in a blocked connection, and ordinary traffic produces no flow. Verified against nDPId 1.7 on both backends; these tests skip themselves unless `BB_REAL_NDPID` names a built nDPId. (tests/e2e.bats: a live BitTorrent connection is detected, its flow is added and the connection is cut) (tests/e2e.bats: ordinary traffic produces no flow)
16. [x] **S7.16** `--no-dpi` gives the static mode without units, users or binary; the build packages are recorded; the new units are valid for `systemd-analyze`. (tests/dpi_install.bats: --no-dpi: static mode) (tests/dpi_install.bats: build packages are installed and recorded) (tests/dpi_install.bats: units: syntax and ordering of the dynamic-layer units are valid for systemd-analyze)
17. [x] **S7.17** `bb uninstall` removes the whole dynamic layer, and a user that was already there stays. (tests/dpi_install.bats: uninstall removes the dynamic layer)
18. [x] **S7.18** `bb doctor` checks the binary, `jq`, the users, the units and the listener configuration. (tests/dpi_install.bats: bb doctor checks the dynamic layer)
19. [~] **S7.19** A progress indicator with the percentage is shown while building. The code is there, but output on a terminal is not tested.
20. [~] **S7.20** The socket and the units start under a real systemd. They are only checked with `systemd-analyze` and `socat` as a stand-in for socket activation here; covered by slice 9.

**Tests:** `tests/dpi.bats` (listener, against the stream recorded from the real nDPId), `tests/dpi_install.bats`, `tests/e2e.bats` (live capture), `tests/fixtures/ndpid-1.7.raw`.

**Not to do:** Python, the nDPIsrvd daemon, parsing JSON in bash or `awk`.

---

### Slice 8: Machine-readable output and logs

**Files:** `src/bb`, `lang/en.sh`, `lang/ru.sh`, `tests/json.bats`.

**What it does:** `--json` for `bb status` and `bb doctor`, `bb log [-f] [-n N]`.

**Acceptance criteria:**

1. [x] **S8.1** `bb status --json` and `bb doctor --json` are valid JSON with stable keys and untranslated values. (tests/json.bats: status --json is valid JSON with stable keys on both backends) (tests/json.bats: status --json reports inactive rules with empty sets) (tests/json.bats: status --json and doctor --json are the same in both languages) (tests/json.bats: doctor --json lists checks with level, stable id and raw arguments) (tests/json.bats: doctor --json keeps the exit code and the untranslated ufw state) (tests/json.bats: doctor --json works on an unconfigured host)
2. [x] **S8.2** Without `jq` a hint is printed and the exit code is non-zero. (tests/json.bats: without jq a hint is printed and the exit code is non-zero, in both languages)
3. [~] **S8.3** `bb log -f` merges the journal tag `bb` and the kernel messages with the prefix `bb:`. The query (`-t bb + _TRANSPORT=kernel`, then a filter on the kernel prefix) is tested against a `journalctl` stand-in only; the behaviour on a real journal is covered by slice 9. (tests/json.bats: bb log merges the journal tag bb and kernel messages with the prefix bb:) (tests/json.bats: bb log -f follows and -n sets the number of lines)

**Tests:** `tests/json.bats`.

**Not to do:** a separate log file or rotation.

---

### Slice 9: Test matrix and CI

**Files:** `.github/workflows/ci.yml`, `tests/matrix/`.

**What it does:** runs the suite on the supported distributions and exercises what the sandbox cannot.

**Acceptance criteria:**

1. [~] **S9.1** The suite passes on Debian, Ubuntu, and on the RHEL family and Fedora. The `suite` job of `ci.yml` runs it in six containers; it has not run yet (it needs GitHub Actions).
2. [~] **S9.2** The `iptables` `legacy` variant passes. The `legacy` job runs the suite after switching the alternatives; it has not run yet.
3. [~] **S9.3** The units start under a real systemd, and a reboot restores the rules. `tests/matrix/host.sh` checks the units and a restart of `bb-firewall` on a CI host; it has not run yet, and a real reboot is not covered.
4. [ ] **S9.4** SELinux enforcing mode raises no AVC denial for `bb`.
5. [~] **S9.5** Docker and k3s restarts do not remove the `bb` rules. `tests/matrix/host.sh` restarts them when present; it has not run yet.
6. [~] **S9.6** IPv6 traffic is blocked on a host with IPv6. `tests/matrix/host.sh` checks the IPv6 sets and that loopback stays reachable; blocking of real IPv6 traffic is covered by the namespace suite, not yet on a CI host.
7. [x] **S9.7** The `wget` download path works. (tests/cli.bats: without curl the download goes through wget with --https-only)

**Tests:** CI jobs (`tests/matrix/`), `tests/cli.bats`.

**Not to do:** support for distributions outside the two families.

---

### Slice 10: Documentation and release

**Files:** `README.md`, `LICENSE`, `CHANGELOG.md`, `.github/workflows/release.yml`, `tests/check-release.sh`.

**What it does:** the user documentation and the release.

**Acceptance criteria:**

1. [x] **S10.1** The README states `Status: under development`, names the license, and does not point to this file. (tests/spec.bats: README)
2. [x] **S10.2** The repository carries the MIT license. (tests/spec.bats: license)
3. [x] **S10.3** `CHANGELOG.md` follows Keep a Changelog. (tests/spec.bats: CHANGELOG.md follows Keep a Changelog)
4. [~] **S10.4** A tag produces a release with checksums, and the version in the CHANGELOG and in the tag agree. The check and the archive with `SHA256SUMS` are tested; the publishing step of `release.yml` has not run yet. (tests/spec.bats: release check: the tag, BB_VERSION and the CHANGELOG must agree)

**Tests:** `tests/spec.bats`.

**Not to do:** a documentation site.

---

## 18. Deviation register

A deviation is a place where the implementation deliberately does something other than what this file says. It is recorded here instead of being left implicit.

**Rules.**

1. Every deviation has a sequential ID `D-NNN`, the section(s) it concerns, what is done instead, why, a status, and the test that verifies the behavior that is actually implemented.
2. The affected text in this file carries `(see D-NNN)`, and the code that deviates carries a `# D-NNN` comment. `tests/check-spec.sh` checks both directions: an active deviation must be annotated, cited by a real test and anchored in `src/` or `tests/`, and no ID may appear anywhere in the repository without an entry here.
3. A deviation is `active` while the difference exists. When this file is changed to say what the code does (or the code is changed back), the entry becomes `resolved` and stays for history; a resolved entry needs no annotation or test.
4. Until the owner folds it into the text above, the register wins for the behavior it describes.

| ID | Spec | Deviation | Reason | Status | Verified by |
|---|---|---|---|---|---|
| D-001 | §6.1, §8 | Container and pod networks (Docker, k3s/k8s) go to separate `internal4/6` sets that exempt a packet only when both its source and its destination are internal. The text adds them to `allow`, which passes a packet when either end matches. Node addresses stay in `allow`. | Taken literally the text would exempt a container that talks to a blocked address, which contradicts the acceptance criterion that traffic from containers and pods to blocked addresses is dropped while traffic between them passes. | active | (tests/integrations.bats: containers/pods talk to each other, but not to blocked addresses) |
| D-002 | §11 | An empty DHT set at the end of `bb install` is a warning in the self-check, not a failure. | An install on a host without working DNS must still complete; `bb list update dht` fills the set later. | active | (tests/install.bats: install without working DNS still completes) |
| D-003 | §9, §12 | Only the notification secrets (tokens, chat, homeserver, room) are stored in `notify.conf`; the other `notify_*` settings live in `bb.conf`. | The text puts "tokens and settings" in `notify.conf` and also lists `notify_*` among the `bb.conf` parameters. Splitting keeps the secrets file minimal and everything else readable. | active | (tests/notify.bats: telegram setup: verified with a test message, secrets only in notify.conf) |
| D-004 | §10 | Additions to the CLI: `bb allow <net> --rm`, `bb log` without `-f` and `bb log -n N`, `bb list` without arguments (shows the lists), `bb notify events [LIST]`, `bb integrate none` and `bb integrate <name>`, `bb uninstall --keep-packages`, and internal commands starting with `__` that units and tests call. | Without them the allowlist could not shrink, the lists could not be inspected, the log could not be read without following it, and the units had nothing to call. | active | (tests/cli.bats: ban/unban/allow edit the source files; ban is idempotent) (tests/json.bats: bb log -f follows and -n sets the number of lines) (tests/integrations.bats: bb integrate: selection, none, auto, errors and status) (tests/install.bats: uninstall --keep-packages leaves packages alone) |
| D-005 | §6.1, §7 | Entries broader than /8 (IPv4) or /16 (IPv6) are rejected in lists and in manual bans and allowlist entries. | One bad line such as `0.0.0.0/0` must not be able to block everything. | active | (tests/cli.bats: norm: invalid and too-broad entries are rejected) |
| D-006 | §10, §13 | An unconfirmed `block` mode is also reverted after a reboot: a marker is kept while the rollback timer runs, and `apply` and `guard` revert the mode when the timer is gone. | The rollback timer is transient and does not survive a reboot, so a host rebooted inside the confirmation window would stay in an unconfirmed `block`. | active | (tests/install.bats: an unconfirmed block mode is reverted by apply/guard when the timer is gone) |
| D-007 | §11 | nDPId is cloned with `git clone --depth 1 --branch <ref>` (a full clone and a checkout when the reference is a commit) and only the `libnDPI` submodule is initialised, instead of `git clone --recursive`. | The other submodules are examples that are never built (`BUILD_EXAMPLES=OFF`) and are hosted on a second server, which makes the build fail on restricted networks. | active | (tests/dpi_install.bats: the build clones the pinned tag and initialises only libnDPI) |
| D-008 | §6.4, §13 | The socket of `bb-listener.socket` belongs to the nDPId user (`SocketUser=bb-ndpid`, mode 0600) and not to root. | The text asks for nDPId to run as a separate user and for a socket that only root can use, which would keep nDPId from connecting. | active | (tests/dpi_install.bats: units: the socket belongs to the nDPId user) |
| D-009 | §6.4, §13 | The listener (user `bb`) reads a root-written copy of its settings from `/var/lib/bb/listener.conf`, writes only to `/var/lib/bb/listener/`, reads the allowlist from the live kernel set, and leaves `rate_limit` notes that the guard turns into notifications (so such a notification can be up to `guard_interval` late). | `bb.conf` and `notify.conf` are root-only, so an unprivileged listener cannot read them or send notifications itself, and a narrower writable path than `/var/lib/bb` keeps it from touching root's files. | active | (tests/dpi_install.bats: the listener runs as an unprivileged user with CAP_NET_ADMIN and nothing else) (tests/dpi.bats: exceeding the rate limit pauses the listener and raises rate_limit once) |
| D-010 | §6.4 | nDPId is started with `-u bb-ndpid -g bb-ndpid -a bb -o max-reader-threads=4`, and the socket accepts 8 connections instead of 4. | Verified on nDPId 1.7: started as an unprivileged user it tries to switch to `nobody` and exits unless `-u` and `-g` name its own user, and it opens one collector connection per reader thread (10 by default), so a limit of 4 would turn most of them away. | active | (tests/dpi_install.bats: units: the socket belongs to the nDPId user) (tests/e2e.bats: a live BitTorrent connection is detected) |
