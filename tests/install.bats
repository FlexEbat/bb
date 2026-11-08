#!/usr/bin/env bats
load helpers

setup() {
	setup_root
	mkdir -p "$R/units" "$R/sbin" "$R/etc-sys"
	printf '#!/bin/sh\n' >"$R/sbin/bb"; chmod +x "$R/sbin/bb"
	export BB_UNIT_DIR=$R/units BB_BIN_PATH=$R/sbin/bb BB_FORCE_IPV6=yes
	printf 'ID=debian\n' >"$R/os-release"; export BB_OS_RELEASE=$R/os-release
	printf 'nameserver 127.0.0.53\nnameserver 198.51.100.53\n' >"$R/resolv.conf"; export BB_RESOLV_FILES=$R/resolv.conf
	export BB_SAVED_FILES=""
	cat >"$R/stubs/systemctl" <<STUB
#!/bin/sh
echo "systemctl \$*" >>"$R/sd.log"
case "\$1" in
	is-enabled) [ -e "$R/enabled.fail" ] && exit 1; exit 0 ;;
	is-active) [ -e "$R/timer.active" ] && exit 0; exit 1 ;;
esac
exit 0
STUB
	cat >"$R/stubs/systemd-run" <<STUB
#!/bin/sh
echo "systemd-run \$*" >>"$R/sd.log"
STUB
	chmod +x "$R/stubs/"*
	export PATH="$R/stubs:$PATH"
}
teardown() { teardown_root; }

has_bb_objects() { nft list tables 2>/dev/null | grep -q 'inet bb'; }

@test "install (nft): config, allowlist, rules in monitor mode, units, no leftovers" {
	topo_up; ip route add default via 198.51.100.2
	SSH_CONNECTION="203.0.113.9 5555 198.51.100.1 22" run bb install --no-dpi --backend nft --yes --iface bbv0
	[ "$status" -eq 0 ]
	[[ $output == *"Self-check passed."* ]]
	grep -q "^backend='nft'" "$BB_CONF_DIR/bb.conf"
	grep -q "^mode='monitor'" "$BB_CONF_DIR/bb.conf"
	grep -q "^iface='bbv0'" "$BB_CONF_DIR/bb.conf"
	run cat "$BB_CONF_DIR/allow.list"
	[[ $output == *198.51.100.2* ]]            # default gateway
	[[ $output == *198.51.100.53* ]]           # DNS server
	[[ $output == *203.0.113.9* ]]             # the SSH client
	[[ $output != *127.0.0.53* ]]              # loopback resolver is not added
	has_bb_objects
	[ ! -e "$BB_UNIT_DIR/bb-sets.service" ]    # nft has no sets service
	for u in bb-firewall.service bb-update.service bb-update.timer bb-guard.service bb-guard.timer; do [ -s "$BB_UNIT_DIR/$u" ]; done
	[ "$(stat -c %a "$BB_UNIT_DIR/bb-guard.timer")" = 644 ]
	grep -q 'enable bb-firewall.service bb-update.timer bb-guard.timer' "$R/sd.log"
	grep -q 'start bb-firewall.service' "$R/sd.log"
	run bash -c "ls '$BB_BACKUP_DIR' | grep -c '^install-'"; [ "$output" = 0 ]   # backup dropped on success
	[ -s "$BB_CONF_DIR/dht.nodes" ]
}

@test "install (iptables): sets service is created and wired in" {
	run bb install --no-dpi --backend iptables --yes --iface lo
	[ "$status" -eq 0 ]
	[ -s "$BB_UNIT_DIR/bb-sets.service" ]
	grep -q '^Wants=bb-sets.service' "$BB_UNIT_DIR/bb-firewall.service"
	grep -q '^Before=.*netfilter-persistent.service.*ufw.service' "$BB_UNIT_DIR/bb-sets.service"
	grep -q '^After=.*nftables.service.*netfilter-persistent.service.*ufw.service' "$BB_UNIT_DIR/bb-firewall.service"
	grep -q '^Before=docker.service k3s.service' "$BB_UNIT_DIR/bb-firewall.service"
	grep -q 'enable bb-sets.service' "$R/sd.log"
	run iptables -t raw -S PREROUTING; [[ ${lines[1]} == "-A PREROUTING -j BB_FILTER" ]]
}

@test "units: syntax and ordering verified by systemd-analyze, no blank line when Wants is absent" {
	command -v systemd-analyze >/dev/null || skip "systemd-analyze not available"
	for b in nft iptables; do
		rm -rf "$R/units"; mkdir -p "$R/units"
		bb __init-config --backend $b
		for u in bb-sets.service bb-firewall.service bb-update.service bb-update.timer bb-guard.service bb-guard.timer; do
			bb __unit $u >"$R/units/$u"
		done
		if [ "$b" = nft ]; then
			rm "$R/units/bb-sets.service"
			refute grep -q 'Wants=' "$R/units/bb-firewall.service"
			refute awk 'prev == "" && $0 == "" && NR > 1 { f = 1 } { prev = $0 } END { exit !f }' "$R/units/bb-firewall.service"
		else
			grep -q '^Wants=bb-sets.service' "$R/units/bb-firewall.service"
		fi
		run systemd-analyze verify "$R"/units/*
		echo "$output"
		[ "$status" -eq 0 ]
		[ -z "$output" ]
	done
	grep -q '^OnUnitActiveSec=300s' "$R/units/bb-guard.timer"
}

@test "install is repeatable: keeps bans and allowlist, no duplicates" {
	bb install --no-dpi --backend nft --yes --iface lo
	bb ban 198.51.100.7
	bb allow 192.0.2.0/24
	bb install --no-dpi --backend nft --yes --iface lo
	run bb status; [[ $output == *"Rules: active"* ]]
	[ "$(grep -c '^198.51.100.7 ' "$BB_CONF_DIR/manual.list")" -eq 1 ]
	[ "$(grep -c '^192.0.2.0/24$' "$BB_CONF_DIR/allow.list")" -eq 1 ]
	[ "$(sort "$BB_CONF_DIR/allow.list" | uniq -d | wc -l)" -eq 0 ]
}

@test "packages: nft path installs exactly the missing logical packages (apt)" {
	printf 'nft\niptables\nipset\nip\n' >"$R/absent"; export BB_TEST_ABSENT_FILE=$R/absent
	cat >"$R/stubs/apt-get" <<STUB
#!/bin/sh
echo "apt-get \$*" >>"$R/pkg.log"
: >"$R/absent"
STUB
	chmod +x "$R/stubs/apt-get"
	run bb install --no-dpi --yes --iface lo
	[ "$status" -eq 0 ]
	grep -q 'apt-get install -y nftables' "$R/pkg.log"
	grep -q 'iproute2' "$R/pkg.log"
	[[ $output == *"Will install: nftables"* ]]
	grep -q "^backend='nft'" "$BB_CONF_DIR/bb.conf"
}

@test "packages: dnf family maps names (iptables-nft, iproute)" {
	printf 'ID=rocky\nID_LIKE="rhel centos fedora"\n' >"$BB_OS_RELEASE"
	printf 'iptables\nipset\nip\nnft\n' >"$R/absent"; export BB_TEST_ABSENT_FILE=$R/absent
	cat >"$R/stubs/dnf" <<STUB
#!/bin/sh
echo "dnf \$*" >>"$R/pkg.log"
: >"$R/absent"
STUB
	chmod +x "$R/stubs/dnf"
	run bb install --no-dpi --backend iptables --yes --iface lo
	[ "$status" -eq 0 ]
	grep -q 'dnf install -y iptables-nft ipset' "$R/pkg.log"
	grep -q 'iproute' "$R/pkg.log"
}

@test "packages: a failing install changes nothing" {
	printf 'nft\n' >"$R/absent"; export BB_TEST_ABSENT_FILE=$R/absent
	printf '#!/bin/sh\nexit 100\n' >"$R/stubs/apt-get"; chmod +x "$R/stubs/apt-get"
	run bb install --no-dpi --backend nft --yes --iface lo
	[ "$status" -ne 0 ]
	[[ $output == *"nothing was changed"* ]]
	[ ! -e "$BB_CONF_DIR/bb.conf" ]
	refute has_bb_objects
	[ ! -e "$BB_UNIT_DIR/bb-firewall.service" ]
}

@test "platform: unknown distribution stops unless --force" {
	printf 'ID=arch\n' >"$BB_OS_RELEASE"
	run bb install --no-dpi --backend nft --yes --iface lo
	[ "$status" -ne 0 ]
	[[ $output == *"unsupported distribution"* ]]
	refute has_bb_objects
	run bb install --no-dpi --backend nft --yes --iface lo --force
	[ "$status" -eq 0 ]
}

@test "arguments are validated before anything changes" {
	for args in "--ports-mode only" "--ports-mode only --ports 99999" "--ports 6881-6880 --ports-mode only" "--ports-mode sideways" "--iface bad;name" "--backend pf"; do
		# shellcheck disable=SC2086
		run bb install --no-dpi --yes --iface lo $args
		[ "$status" -ne 0 ]
	done
	[ ! -e "$BB_CONF_DIR/bb.conf" ]
	refute has_bb_objects
}

@test "port mode flags end up in the config and in the rules" {
	bb install --no-dpi --backend nft --yes --iface lo --ports-mode except --ports 6881-6889,51413
	grep -q "^ports_mode='except'" "$BB_CONF_DIR/bb.conf"
	grep -q "^ports='6881-6889,51413'" "$BB_CONF_DIR/bb.conf"
	run nft list chain inet bb bb_dht
	[[ $output == *"6881-6889"* && $output == *51413* ]]
}

@test "failed self-check keeps the backup and says where it is" {
	touch "$R/enabled.fail"
	run bb install --no-dpi --backend nft --yes --iface lo
	[ "$status" -ne 0 ]
	[[ $output == *"self-check failed"* ]]
	[[ $output == *"is not enabled"* ]]
	[[ $output == *"backup was kept at $BB_BACKUP_DIR/install-"* ]]
	ls -d "$BB_BACKUP_DIR"/install-* >/dev/null
}

@test "install output is fully Russian with --lang ru" {
	run bb install --no-dpi --lang ru --backend nft --yes --iface lo
	[ "$status" -eq 0 ]
	[[ $output == *"Самопроверка пройдена."* ]]
	[[ $output == *"Резервная копия"* ]]
	[[ $output != *"Self-check"* ]]
	grep -q "^lang='ru'" "$BB_CONF_DIR/bb.conf"
}

@test "uninstall removes everything of bb, only bb objects of the firewall, and cleans saved rule files" {
	mkdir -p "$R/saved"
	cat >"$R/saved/rules.v4" <<'SAVE'
*raw
:PREROUTING ACCEPT [0:0]
:BB_FILTER - [0:0]
-A PREROUTING -j BB_FILTER
-A BB_FILTER -m set --match-set bb_manual4 src -j DROP
COMMIT
*filter
-A INPUT -s 9.9.9.9 -j DROP
COMMIT
SAVE
	cat >"$R/saved/ipsets" <<'SAVE'
create bb_manual4 hash:net family inet timeout 0
add bb_manual4 1.2.3.4
create mine hash:ip
add mine 5.6.7.8
SAVE
	chmod 640 "$R/saved/rules.v4"
	export BB_SAVED_FILES="$R/saved/rules.v4 $R/saved/ipsets $R/saved/missing"
	bb install --no-dpi --backend iptables --yes --iface lo
	nft add table inet foreign
	iptables -t filter -A INPUT -s 8.8.4.4 -j DROP
	ipset create foreign_set hash:ip
	run bb uninstall --yes
	[ "$status" -eq 0 ]
	[[ $output == *"bb has been removed completely."* ]]
	run nft list tables; [[ $output != *"inet bb"* && $output == *foreign* ]]
	run iptables -S INPUT; [[ $output == *8.8.4.4* ]]
	run iptables -t raw -S; [[ $output != *BB_FILTER* ]]
	run ipset list -n; [[ $output != *bb_* && $output == *foreign_set* ]]
	refute grep -q 'BB_FILTER\|bb_' "$R/saved/rules.v4" "$R/saved/ipsets"
	grep -q 'INPUT -s 9.9.9.9' "$R/saved/rules.v4"
	grep -q '^add mine 5.6.7.8' "$R/saved/ipsets"
	[ "$(stat -c %a "$R/saved/rules.v4")" = 640 ]
	for u in bb-sets.service bb-firewall.service bb-update.timer bb-guard.timer; do [ ! -e "$BB_UNIT_DIR/$u" ]; done
	grep -q 'disable bb-guard.timer' "$R/sd.log"
	[ ! -e "$BB_CONF_DIR" ] && [ ! -e "$BB_STATE_DIR" ] && [ ! -e "$BB_BACKUP_DIR" ]   # nothing of bb's own is left
	[ ! -e "$BB_SHARE_DIR" ] && [ ! -e "$BB_BIN_PATH" ]
}

@test "uninstall needs --yes without a terminal, then removes configuration, state and the lock" {
	bb install --no-dpi --backend nft --yes --iface lo
	run bb uninstall </dev/null
	[ "$status" -ne 0 ]
	has_bb_objects
	[ -e "$BB_CONF_DIR/bb.conf" ]
	run bb uninstall --yes
	[ "$status" -eq 0 ]
	[ ! -e "$BB_CONF_DIR" ] && [ ! -e "$BB_STATE_DIR" ] && [ ! -e "$BB_LOCK_FILE" ]
	refute has_bb_objects
}

# ---- packages that bb itself installed ------------------------------------------------------------
@test "uninstall (apt) removes the packages bb installed, dependencies included, and nothing else" {
	pkg_stubs apt; printf 'nft\n' >"$R/absent"
	bb install --no-dpi --backend nft --yes --iface lo >/dev/null
	grep -qx 'pkg apt:nftables' "$BB_STATE_DIR/manifest"
	grep -qx 'pkg apt:nftables-deps' "$BB_STATE_DIR/manifest"          # a dependency pulled in by the install
	refute grep -q 'libpreexisting' "$BB_STATE_DIR/manifest"          # what was there before is not ours
	run bb uninstall --yes
	[ "$status" -eq 0 ]
	[[ $output == *"Removed the packages bb had installed: "* ]]
	grep -q 'apt-get purge -y -- ' "$R/pkg.log"
	[ "$(cat "$R/pkgs.state")" = libpreexisting ]
}

@test "uninstall keeps a package other software depends on, and says so" {
	pkg_stubs apt; printf 'nft\n' >"$R/absent"
	bb install --no-dpi --backend nft --yes --iface lo >/dev/null
	printf 'firewalld\n' >"$R/pkgs.extra"                              # purging would also remove firewalld
	run bb uninstall --yes
	[ "$status" -eq 0 ]
	[[ $output == *"Kept the packages bb had installed"*"firewalld"* ]]
	refute grep -q 'apt-get purge -y' "$R/pkg.log"
	grep -qx nftables "$R/pkgs.state"
	[ ! -e "$BB_CONF_DIR" ]                                           # everything else is gone regardless
}

@test "uninstall --keep-packages leaves packages alone" {
	pkg_stubs apt; printf 'nft\n' >"$R/absent"
	bb install --no-dpi --backend nft --yes --iface lo >/dev/null
	run bb uninstall --yes --keep-packages
	[ "$status" -eq 0 ]
	refute grep -q 'apt-get' <(grep -v 'install' "$R/pkg.log")
	grep -qx nftables "$R/pkgs.state"
}

@test "uninstall (dnf) removes what bb installed unless something requires it" {
	pkg_stubs dnf; printf 'nft\n' >"$R/absent"
	bb install --no-dpi --backend nft --yes --iface lo >/dev/null
	grep -qx 'pkg dnf:nftables' "$BB_STATE_DIR/manifest"
	run bb uninstall --yes
	[[ $output == *"Removed the packages bb had installed"* ]]
	grep -q 'dnf remove -y -- ' "$R/pkg.log"
	[ "$(cat "$R/pkgs.state")" = libpreexisting ]
}

@test "uninstall (dnf) keeps packages that other installed software requires" {
	pkg_stubs dnf; printf 'nft\n' >"$R/absent"
	bb install --no-dpi --backend nft --yes --iface lo >/dev/null
	printf 'firewalld\n' >"$R/pkgs.extra"
	run bb uninstall --yes
	[[ $output == *"Kept the packages bb had installed"* ]]
	refute grep -q 'dnf remove' "$R/pkg.log"
}

@test "a failed package installation is still recorded so that uninstall can clean it up" {
	pkg_stubs apt; printf 'nft\n' >"$R/absent"
	cat >"$R/stubs/apt-get" <<STUB
#!/bin/sh
echo "apt-get \$*" >>"$R/pkg.log"
[ "\$1" = install ] && { echo nftables >>"$R/pkgs.state"; exit 100; }
exit 0
STUB
	run bb install --no-dpi --backend nft --yes --iface lo
	[ "$status" -ne 0 ]
	grep -qx 'pkg apt:nftables' "$BB_STATE_DIR/manifest"
}

@test "an unconfirmed block mode is reverted by apply/guard when the timer is gone" {
	bb install --no-dpi --backend nft --yes --iface lo
	touch "$R/timer.active"
	bb mode block --confirm 30
	[ -e "$BB_STATE_DIR/mode.pending" ]
	run bb apply; [ "$status" -eq 0 ]          # timer still running: leave block alone
	run bb mode; [[ $output == *block* ]]
	rm "$R/timer.active"                       # "reboot": the transient timer is gone
	run bb apply
	[[ $output == *"never confirmed"* ]]
	run bb mode; [[ $output == *monitor* ]]
	[ ! -e "$BB_STATE_DIR/mode.pending" ]
}

@test "confirm clears the pending marker so block survives a reboot" {
	bb install --no-dpi --backend nft --yes --iface lo
	touch "$R/timer.active"
	bb mode block --confirm 30
	bb mode confirm
	[ ! -e "$BB_STATE_DIR/mode.pending" ]
	rm -f "$R/timer.active"
	bb apply
	run bb mode; [[ $output == *block* ]]
}

@test "boot path: __sets-restore recreates sets and bans without any rules" {
	bb install --no-dpi --backend iptables --yes --iface lo
	bb ban 198.51.100.7
	bb __remove
	run iptables -t raw -S; [[ $output != *BB_FILTER* ]]
	bb __sets-restore
	ipset test bb_manual4 198.51.100.7
	run iptables -t raw -S; [[ $output != *BB_FILTER* ]]
	bb apply
	run bb status; [[ $output == *"Rules: active"* ]]
}

@test "backend: iptables without the nftables package is used as is, and jq is not installed in basic mode" {
	pkg_stubs apt; printf 'nft\n' >"$R/absent"
	run bb install --no-dpi --yes --iface lo
	[ "$status" -eq 0 ]
	grep -q "^backend='iptables'" "$BB_CONF_DIR/bb.conf"
	[[ $output == *"Nothing to install."* ]]
	refute grep -q 'install' "$R/pkg.log" 2>/dev/null
	refute grep -qw jq "$R/pkg.log" 2>/dev/null
}

@test "install without working DNS still completes: the empty DHT set is only a warning" {
	printf 'unresolvable.invalid:6881\n' >"$BB_CONF_DIR/dht.nodes" 2>/dev/null || { mkdir -p "$BB_CONF_DIR"; printf 'unresolvable.invalid:6881\n' >"$BB_CONF_DIR/dht.nodes"; }
	run bb install --no-dpi --backend nft --yes --iface lo
	[ "$status" -eq 0 ]
	[[ $output == *"the DHT set is empty"* && $output == *"Self-check passed."* ]]
}
