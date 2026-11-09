#!/usr/bin/env bats
# Regression tests for the findings of the code review (see tech.md, "Review fixes").
load helpers

setup() {
	setup_root
	mkdir -p "$R/sbin"; printf '#!/bin/sh\n' >"$R/sbin/bb"; chmod +x "$R/sbin/bb"
	export BB_BIN_PATH=$R/sbin/bb
	cat >"$R/stubs/logger" <<STUB
#!/bin/sh
echo "\$*" >>"$R/logger.log"
STUB
	printf '#!/bin/sh\nexit 0\n' >"$R/stubs/systemctl"
	chmod +x "$R/stubs/"*
	export PATH="$R/stubs:$PATH"
}
teardown() { teardown_root; }

# R1: a list that does not fit into its set must not leave the host without rules
@test "R1: apply and guard still install the rules when the list set cannot be loaded (iptables)" {
	bb __init-config --backend iptables --ipv6 no >/dev/null
	setcfg list_maxelem 2
	mkdir -p "$BB_STATE_DIR/lists"
	printf '198.51.100.1\n198.51.100.2\n198.51.100.3\n198.51.100.4\n' >"$BB_STATE_DIR/lists/big.list"
	run bb apply
	[ "$status" -eq 0 ]
	[[ $output == *"could not load set list4"* && $output == *"applied without it"* ]]
	bb status --json | jq -e '.rules == "active"' >/dev/null
	grep -q 'list_update_failed name=list reason=load' "$R/logger.log"
	# the guard restores the rules after a flush, in spite of the same list
	iptables -t raw -F PREROUTING; iptables -t raw -F OUTPUT
	run bb status --json
	jq -e '.rules == "inactive"' <<<"$output" >/dev/null
	run bb guard
	[ "$status" -eq 0 ]
	bb status --json | jq -e '.rules == "active"' >/dev/null
}

@test "R1: an oversized list is rejected on update and the old data is kept (iptables)" {
	bb __init-config --backend iptables --ipv6 no >/dev/null
	setcfg list_maxelem 3
	printf '198.51.100.1\n198.51.100.2\n' >"$R/small.txt"
	bb list add t "$R/small.txt" >/dev/null
	run bb list update t; [ "$status" -eq 0 ]
	printf '198.51.100.1\n198.51.100.2\n198.51.100.3\n198.51.100.4\n198.51.100.5\n' >"$R/small.txt"
	run bb list update t
	[ "$status" -ne 0 ]
	[[ $output == *"more than list_maxelem"* ]]
	[ "$(wc -l <"$BB_STATE_DIR/lists/t.list")" -eq 2 ]
}

# R4: the lock is not held while the network is used, and a busy lock is not a failure of the guard
@test "R4: list update downloads without holding the lock" {
	bb __init-config --backend nft --ipv6 no >/dev/null
	cat >"$R/stubs/curl" <<STUB
#!/bin/sh
if flock -n "$BB_LOCK_FILE" true; then echo free >>"$R/lockstate"; else echo held >>"$R/lockstate"; fi
printf '198.51.100.30\n198.51.100.31\n'
STUB
	chmod +x "$R/stubs/curl"
	bb list add w https://example.com/w.txt >/dev/null
	run bb list update w
	[ "$status" -eq 0 ]
	[ "$(cat "$R/lockstate")" = free ]
	grep -q 198.51.100.30 "$BB_STATE_DIR/lists/w.list"
}

@test "R4: bb guard with a busy lock exits 0 and says so in the journal instead of failing" {
	bb __init-config --backend nft --ipv6 no >/dev/null
	bb apply >/dev/null
	(flock 8; sleep 6) 8>"$BB_LOCK_FILE" &
	sleep 0.5
	BB_LOCK_WAIT=1 run bb guard
	[ "$status" -eq 0 ]
	grep -q 'guard_skipped reason=lock' "$R/logger.log"
	# the other commands still report a busy lock
	BB_LOCK_WAIT=1 run bb ban 198.51.100.9
	[ "$status" -ne 0 ]
	wait
}

# R3: the interface of nDPId
@test "R3: with inspection on and no interface, install stops and doctor fails" {
	run bb install --backend nft --yes
	[ "$status" -ne 0 ]
	[[ $output == *"--iface NAME"* ]]
	bb __init-config --backend nft --ipv6 no >/dev/null
	setcfg dpi yes
	run bb doctor --json
	jq -e '[.checks[] | select(.id == "dpi_iface_empty" and .level == "fail")] | length == 1' <<<"$output" >/dev/null
	setcfg iface nosuchif0
	run bb doctor --json
	jq -e '[.checks[] | select(.id == "dpi_iface_missing")][0].args == ["nosuchif0"]' <<<"$output" >/dev/null
	setcfg iface lo
	run bb doctor --json
	jq -e '[.checks[] | select(.id == "dpi_iface_ok")][0].args == ["lo"]' <<<"$output" >/dev/null
}

# R2: no configuration value may contain a quote
@test "R2: cfg_valid refuses a single quote in any value" {
	run bash -c 'source <(sed -n "/^cfg_valid()/,/^}/p;/^is_uint()/,/^}/p" "$1"); notify_events_valid() { :; }
		cfg_valid notify_proxy "http://proxy.example:3128" || exit 10
		cfg_valid notify_proxy "http://a'"'"'b:1" && exit 11
		cfg_valid iface "a'"'"'b" && exit 12
		exit 0' _ "$BATS_TEST_DIRNAME/../src/bb"
	[ "$status" -eq 0 ]
}

# R6: the rules go in before the network comes up
@test "R6: bb-firewall.service is ordered before network-pre.target, not after it" {
	bb __init-config --backend nft --ipv6 no >/dev/null
	run bb __unit bb-firewall.service
	[[ $output == *"Before=network-pre.target"* && $output == *"Wants=network-pre.target"* ]]
	after=$(grep '^After=' <<<"$output")
	[[ $after != *network-pre* ]]
	if command -v systemd-analyze >/dev/null; then
		mkdir -p "$R/u"; bb __unit bb-firewall.service >"$R/u/bb-firewall.service"
		run systemd-analyze verify --man=no "$R/u/bb-firewall.service"
		[[ $output != *"ordering cycle"* ]]
	fi
}

# R7: the frame reader
@test "R7: the listener bounds a frame's memory with the unit's MemoryMax" {
	bb __init-config --backend nft --ipv6 no >/dev/null
	run bb __unit 'bb-listener@.service'
	[[ $output == *"MemoryMax="* ]]
}

# R8: dynamic flows block the real tuple on both backends 
udp_from() { # sport dport: does a datagram from 198.51.100.1:sport reach the peer's dport?
	: >"$R/udp.out"
	ip netns exec bbpeer sh -c "timeout 4 nc -u -l $2 >'$R/udp.out'" &
	local pid=$!
	sleep 0.5
	printf 'hello\n' | timeout 3 nc -u -w1 -p "$1" 198.51.100.2 "$2" 2>/dev/null
	sleep 0.4; kill "$pid" 2>/dev/null; pkill -f "nc -u -l" 2>/dev/null; wait "$pid" 2>/dev/null || true
	[ -s "$R/udp.out" ]
}

t_flow_tuple() {
	topo_up
	bb __init-config --backend "$1" --ipv6 no >/dev/null
	bb apply >/dev/null
	bb mode block >/dev/null
	# two flows that share nothing with the packets below, and the exact flow we want blocked
	bb __flow-add 4 198.51.100.1 1111 203.0.113.9 2222 udp 600 >/dev/null
	bb __flow-add 4 203.0.113.7 3333 198.51.100.2 4444 udp 600 >/dev/null
	bb __flow-add 4 198.51.100.1 5555 198.51.100.2 6666 udp 600 >/dev/null
	# 1111 -> 4444 is a mix of the first two flows: it is not a flow and must pass
	udp_from 1111 4444
	# the exact flow is cut
	refute udp_from 5555 6666
	# the reply direction of a known flow is cut too, an unrelated port still passes
	udp_from 5556 6666
}
@test "R8: nft: only the exact tuple of a flow is blocked" { t_flow_tuple nft; }
@test "R8: iptables: a mix of two unrelated flows is not blocked, the exact tuple is " { t_flow_tuple iptables; }

@test "R8: iptables: flow sets of the old type are replaced on apply and the rules come back" {
	bb __init-config --backend iptables --ipv6 no >/dev/null
	bb apply >/dev/null
	iptables -t raw -F BB_FILTER
	for k in src dst; do
		ipset destroy "bb_flow_$k"4
		ipset create "bb_flow_$k"4 hash:ip,port family inet timeout 3600
	done
	ipset add bb_flow_src4 203.0.113.1,tcp:1 timeout 3600
	run bb apply
	[ "$status" -eq 0 ]
	ipset list -t bb_flow_src4 | grep -q 'Type: hash:ip,port,ip'
	ipset list -t bb_flow_dst4 | grep -q 'Type: hash:ip,port,ip'
	bb status --json | jq -e '.rules == "active"' >/dev/null
	iptables -t raw -S BB_FILTER | grep -q 'bb_flow_src4 src,src,dst'
}

# R5: name resolution is parallel and has an overall budget
hosts_list() { # count -> a list file with that many names
	local i; : >"$R/hosts.txt"
	for i in $(seq 1 "$1"); do echo "h$i.test.example" >>"$R/hosts.txt"; done
}
slow_getent() { # seconds per name
	cat >"$R/stubs/getent" <<STUB
#!/bin/sh
[ "\$1" = ahosts ] || exec /usr/bin/getent "\$@"
sleep $1
n=\$(printf '%s' "\$2" | tr -dc '0-9')
echo "198.51.100.\$n \$2"
STUB
	chmod +x "$R/stubs/getent"
}

@test "R5: many names are resolved in parallel, not one after another" {
	bb __init-config --backend nft --ipv6 no >/dev/null
	slow_getent 2
	hosts_list 32                                  # 32 names x 2 s: 64 s one by one
	bb list add t "$R/hosts.txt" >/dev/null
	start=$SECONDS
	run bb list update t
	[ "$status" -eq 0 ]
	[ $((SECONDS - start)) -lt 20 ]
	[ "$(wc -l <"$BB_STATE_DIR/lists/t.list")" -eq 32 ]
}

@test "R5: resolve_budget cuts the resolution off, with a warning, and keeps the old data" {
	bb __init-config --backend nft --ipv6 no >/dev/null
	setcfg resolve_budget 2
	slow_getent 4
	hosts_list 4
	bb list add t "$R/hosts.txt" >/dev/null
	mkdir -p "$BB_STATE_DIR/lists"
	printf '198.51.100.200\n' >"$BB_STATE_DIR/lists/t.list"; printf "count='1'\nupdated='1'\n" >"$BB_STATE_DIR/lists/t.meta"
	start=$SECONDS
	run bb list update t
	[ "$status" -ne 0 ]
	[ $((SECONDS - start)) -lt 12 ]
	[[ $output == *"cut off after 2 seconds"* ]]
	[ "$(cat "$BB_STATE_DIR/lists/t.list")" = 198.51.100.200 ]
}

# show flows, the fill of the flow set, and a clock that went backwards
@test "show flows: --limit and --all, a default cap, bad arguments, both languages" {
	bb __init-config --backend nft --ipv6 no >/dev/null; bb apply >/dev/null
	for p in 1 2 3 4 5; do bb __flow-add 4 203.0.113.1 $p 198.51.100.1 6881 tcp 600 >/dev/null; done
	run bb show flows --limit 2
	[ "$(grep -c '^  ' <<<"$output")" -eq 2 ]
	[[ $output == *"and 3 more"* ]]
	run bb --lang ru show flows --limit 2
	[[ $output == *"и ещё 3"* ]]
	run bb show flows --all
	[ "$(grep -c '^  ' <<<"$output")" -eq 5 ]; [[ $output != *"more"* ]]
	run bb show flows
	[ "$(grep -c '^  ' <<<"$output")" -eq 5 ]
	run bb show flows --limit 0; [ "$status" -ne 0 ]
	run bb show flows --limit; [ "$status" -ne 0 ]
	run bb show flows --bogus; [ "$status" -ne 0 ]
	run bb show flows --help; [[ $output == *"--limit N"* ]]
}

@test "doctor warns when a flow set is almost full" {
	bb __init-config --backend nft --ipv6 no >/dev/null
	setcfg dpi yes; setcfg flow_maxelem 5; setcfg iface lo
	bb apply >/dev/null
	run bb doctor --json
	jq -e '[.checks[] | select(.id == "flows_full")] | length == 0' <<<"$output" >/dev/null
	for p in 1 2 3 4; do bb __flow-add 4 203.0.113.1 $p 198.51.100.1 6881 tcp 600 >/dev/null; done
	run bb doctor --json
	jq -e '[.checks[] | select(.id == "flows_full")][0] | .level == "warn" and .args == ["flow4", "4", "5"]' <<<"$output" >/dev/null
}

@test "saved flows are not given a longer life when the clock is behind the saved time" {
	bb __init-config --backend nft --ipv6 no >/dev/null; bb apply >/dev/null
	printf '# saved %s\nnft\tflow4\t203.0.113.1 . 1 . 198.51.100.1 . 2\t600\n' "$(($(date +%s) + 100000))" >"$BB_STATE_DIR/flows.save"
	nft delete table inet bb
	bb apply >/dev/null
	run bb show flows
	left=$(awk '/^  /{ print $NF; exit }' <<<"$output"); left=${left%s}
	[ -n "$left" ] && [ "$left" -le 600 ] && [ "$left" -gt 0 ]
}

# R9: a host with IPv6 whose ip6tables cannot use the raw table (seen on a CI kernel with legacy iptables)
@test "R9: ip6tables without a usable raw table: IPv4 is still blocked, with a warning, and doctor says so" {
	bb __init-config --backend iptables --ipv6 yes >/dev/null
	cat >"$R/stubs/ip6tables" <<'STUB'
#!/bin/sh
echo "ip6tables v1.8.9 (legacy): can't initialize ip6tables table 'raw': Address family not supported by protocol" >&2
exit 3
STUB
	chmod +x "$R/stubs/ip6tables"
	run bb apply
	[ "$status" -eq 0 ]
	[[ $output == *"cannot use the raw table"* ]]
	bb status --json | jq -e '.rules == "active"' >/dev/null
	iptables -t raw -S BB_FILTER | grep -q 'bb_manual4'
	! ipset list -n | grep -q '6$'
	run bb ban 198.51.100.40
	[ "$status" -eq 0 ]
	ipset test bb_manual4 198.51.100.40
	run bb doctor --json
	jq -e '[.checks[] | select(.id == "ipv6_unusable" and .level == "warn")] | length == 1' <<<"$output" >/dev/null
	run bb --lang ru doctor
	[[ $output == *"таблицу raw"* ]]
}
