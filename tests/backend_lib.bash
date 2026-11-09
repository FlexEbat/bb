# Backend scenarios; each takes the backend name (nft | iptables).
init_fw() { bb __init-config --backend "$1" --ipv6 yes; }

t_manual_block() {
	init_fw "$1"; bb apply
	bb ban 198.51.100.2
	assert_reach 198.51.100.2                 # monitor: counted, not dropped
	bb mode block
	assert_blocked 198.51.100.2
	run bb status
	[[ $output =~ manual[[:space:]]+packets[[:space:]]+[1-9] ]]
	bb unban 198.51.100.2
	assert_reach 198.51.100.2
}

t_allow_wins() {
	init_fw "$1"; bb allow 198.51.100.2; bb ban 198.51.100.0/24; bb apply; bb mode block
	assert_reach 198.51.100.2
	bb allow 198.51.100.2 --rm
	assert_blocked 198.51.100.2
}

t_inbound_blocked() { # the peer is the one that is banned: replies/inbound are dropped too
	init_fw "$1"; bb ban 198.51.100.2; bb apply; bb mode block
	if ip netns exec bbpeer ping -c1 -W1 198.51.100.1 >/dev/null 2>&1; then return 1; fi
}

t_loopback_untouched() {
	init_fw "$1"; bb ban 127.0.0.1/32 2>/dev/null || true
	bb apply; bb mode block
	ping -c1 -W1 127.0.0.1 >/dev/null
}

t_ttl_expires() {
	init_fw "$1"; bb apply; bb mode block
	bb ban 198.51.100.2 --ttl 2s
	assert_blocked 198.51.100.2
	sleep 3
	assert_reach 198.51.100.2
	bb apply                                   # expired lines are pruned
	[ ! -s "$BB_CONF_DIR/manual.list" ]
}

t_ttl_survives_apply() {
	init_fw "$1"; bb ban 198.51.100.2 --ttl 1h; bb apply; bb mode block
	assert_blocked 198.51.100.2
}

t_list_block() {
	init_fw "$1"
	printf '198.51.100.2\n' >"$R/l.txt"
	bb list add t "$R/l.txt"; bb apply; bb list update t   # live refresh of the running sets
	assert_reach 198.51.100.2
	bb mode block
	assert_blocked 198.51.100.2
	bb list rm t
	assert_reach 198.51.100.2
}

t_list_atomic() {
	init_fw "$1"; bb apply
	seq -f '198.51.100.%g' 100 2 118 >"$R/l.txt"
	bb list add t "$R/l.txt"; bb list update t
	run bb status; [[ $output =~ list4[[:space:]]+10$'\n' ]]
	: >"$R/l.txt"                              # empty list -> rejected, old set stays
	run bb list update t; [ "$status" -ne 0 ]
	run bb status; [[ $output =~ list4[[:space:]]+10$'\n' ]]
	printf '198.51.100.100\n198.51.100.102\n' >"$R/l.txt"   # shrank below 50% -> rejected
	run bb list update t; [ "$status" -ne 0 ]
	run bb status; [[ $output =~ list4[[:space:]]+10$'\n' ]]
	rm "$R/l.txt"                              # source vanished -> failed, old set stays
	run bb list update t; [ "$status" -ne 0 ]
	run bb status; [[ $output =~ list4[[:space:]]+10$'\n' ]]
}

t_list_overlap() { # overlapping and duplicate networks from several lists load fine
	init_fw "$1"; bb apply
	printf '198.51.100.2:6881\n' >"$BB_CONF_DIR/dht.nodes"
	printf '198.51.100.0/24\n198.51.100.0/25\n198.51.100.7\n' >"$R/a.txt"
	printf '198.51.100.0/25\n198.51.100.200\n' >"$R/b.txt"
	bb list add a "$R/a.txt"; bb list add b "$R/b.txt"
	bb list update
	bb mode block
	assert_blocked 198.51.100.2
}

t_flow_tuple() {
	local base=40000                           # per-backend port range: TIME_WAIT outlives a test
	[[ $1 == nft ]] || base=41000
	init_fw "$1"; bb apply; tcp_listen 8080
	tcp_ok $((base + 10)) 8080                 # no flow yet
	bb __flow-add 4 198.51.100.1 $((base + 20)) 198.51.100.2 8080 tcp
	bb __flow-add 4 198.51.100.1 $((base + 21)) 198.51.100.2 8080 tcp
	tcp_ok $((base + 20)) 8080                 # monitor: still passes
	bb mode block
	if tcp_ok $((base + 21)) 8080; then echo "flow not dropped"; return 1; fi
	tcp_ok $((base + 22)) 8080                 # other source port: no collateral damage
	run bb status; [[ $output =~ flow[[:space:]]+packets[[:space:]]+[1-9] ]]
}

t_dht_modes() {
	init_fw "$1"
	printf '198.51.100.2:6881\n' >"$BB_CONF_DIR/dht.nodes"
	bb apply; bb list update dht
	udp_delivered 6881
	bb mode block
	if udp_delivered 6881; then echo "dht not dropped"; return 1; fi
	udp_delivered 6882                         # a different port of the same host is untouched
	setcfg ports_mode except; setcfg ports 6881; bb apply
	udp_delivered 6881
	setcfg ports_mode only; setcfg ports 7000; bb apply
	udp_delivered 6881
	setcfg ports ' 6000-6900'; true
	setcfg ports 6000-6900; bb apply
	if udp_delivered 6881; then echo "dht not dropped in only-mode"; return 1; fi
}

t_dht_hostnames() {
	init_fw "$1"
	cp /etc/hosts "$R/hosts"
	printf '198.51.100.2 dht.test.example\n10.0.0.9 priv.test.example\n' >>"$R/hosts"
	mount --bind "$R/hosts" /etc/hosts
	printf 'dht.test.example:6881\npriv.test.example:6881\nnone.test.example:6881\nbad line\n' >"$BB_CONF_DIR/dht.nodes"
	bb apply; bb list update dht 2>/dev/null
	umount /etc/hosts
	run cat "$BB_STATE_DIR/dht.list"
	[ "$output" = "198.51.100.2,udp:6881" ]
}

t_dht_empty_keeps() {
	init_fw "$1"
	printf '198.51.100.2:6881\n' >"$BB_CONF_DIR/dht.nodes"
	bb apply; bb list update dht
	printf 'none.test.example:6881\n' >"$BB_CONF_DIR/dht.nodes"
	run bb list update dht; [ "$status" -ne 0 ]
	run cat "$BB_STATE_DIR/dht.list"; [ "$output" = "198.51.100.2,udp:6881" ]
}

t_ipv6_block() {
	if [[ $1 == iptables ]] && ! ip6tables -w -t raw -S >/dev/null 2>&1; then skip "ip6tables cannot use the raw table here"; fi
	init_fw "$1"; bb apply
	if ! ping -6 -c1 -W1 fd99::2 >/dev/null 2>&1; then skip "IPv6 not usable in this environment"; fi
	bb ban fd99::2; bb mode block
	if ping -6 -c1 -W1 fd99::2 >/dev/null 2>&1; then return 1; fi
	bb unban fd99::2
	ping -6 -c1 -W1 fd99::2 >/dev/null
}

t_guard_restores() {
	init_fw "$1"; bb ban 198.51.100.2; bb apply; bb mode block
	bb guard                                   # healthy: silent no-op
	if [[ $1 == nft ]]; then nft flush ruleset; else iptables -t raw -F BB_FILTER; iptables -t raw -D PREROUTING -j BB_FILTER; fi
	assert_reach 198.51.100.2                  # protection really is gone
	bb guard
	assert_blocked 198.51.100.2
	run bb status; [[ $output == *"Rules: active"* ]]
}

t_guard_reorders() { # iptables only: another tool inserts itself above our jump
	init_fw iptables; bb apply
	iptables -t raw -I PREROUTING 1 -s 1.2.3.4 -j ACCEPT
	iptables -t raw -I OUTPUT 1 -s 1.2.3.4 -j ACCEPT
	run iptables -t raw -S PREROUTING; [[ ${lines[1]} == "-A PREROUTING -s 1.2.3.4/32 -j ACCEPT" ]]
	bb guard
	run iptables -t raw -S PREROUTING; [[ ${lines[1]} == "-A PREROUTING -j BB_FILTER" ]]
	run iptables -t raw -S OUTPUT; [[ ${lines[1]} == "-A OUTPUT -j BB_FILTER" ]]
	[ "$(iptables -t raw -S PREROUTING | grep -c 'BB_FILTER$')" -eq 1 ]
	iptables -t raw -S PREROUTING | grep -q -- '-s 1.2.3.4/32 -j ACCEPT'   # theirs is untouched
	bb apply; bb apply                         # repeated apply never duplicates the jump
	[ "$(iptables -t raw -S PREROUTING | grep -c 'BB_FILTER$')" -eq 1 ]
}

t_remove_only_ours() {
	init_fw "$1"; bb apply
	nft add table inet foreign
	nft add chain inet foreign c '{ type filter hook input priority 0; }'
	nft add rule inet foreign c counter
	iptables -t raw -N FOREIGN_CHAIN 2>/dev/null
	iptables -t filter -A INPUT -s 9.9.9.9 -j DROP
	ipset create foreign_set hash:ip
	bb __remove
	run nft list tables; [[ $output != *"inet bb"* ]]; [[ $output == *"inet foreign"* ]]
	run iptables -t raw -S; [[ $output != *BB_FILTER* ]]; [[ $output == *FOREIGN_CHAIN* ]]
	run iptables -S INPUT; [[ $output == *9.9.9.9* ]]
	run ipset list -n; [[ $output != *bb_* ]]; [[ $output == *foreign_set* ]]
	bb apply                                   # and it comes back cleanly
	run bb status; [[ $output == *"Rules: active"* ]]
}

t_coexist_foreign_accept() { # foreign ACCEPT in raw must not shield blocked traffic
	init_fw "$1"; bb ban 198.51.100.2; bb apply; bb mode block
	iptables -t raw -I PREROUTING 1 -j ACCEPT 2>/dev/null
	iptables -t raw -I OUTPUT 1 -j ACCEPT 2>/dev/null
	bb guard
	assert_blocked 198.51.100.2
}

t_prio_change() { # nft: a changed hook_priority recreates the base chains
	init_fw nft; bb apply
	setcfg hook_priority -150; bb apply
	run nft list chain inet bb prerouting; [[ $output == *"mangle"* || $output == *"-150"* ]]
	bb guard
	run bb status; [[ $output == *"Rules: active"* ]]
}

t_mode_confirm() {
	init_fw "$1"; bb apply
	cat >"$R/stubs/systemd-run" <<STUB
#!/bin/sh
echo "systemd-run \$*" >>"$R/sd.log"
STUB
	cat >"$R/stubs/systemctl" <<STUB
#!/bin/sh
echo "systemctl \$*" >>"$R/sd.log"
STUB
	chmod +x "$R/stubs/"*
	PATH="$R/stubs:$PATH" bb mode block --confirm 45
	grep -q -- '--on-active=45s' "$R/sd.log"
	grep -q -- 'mode monitor --rollback' "$R/sd.log"
	run bb mode; [[ $output == *block* ]]
	PATH="$R/stubs:$PATH" bb mode confirm
	grep -q 'stop bb-mode-rollback.timer' "$R/sd.log"
	PATH="$R/stubs:$PATH" bb mode monitor --rollback   # what the timer runs
	run bb mode; [[ $output == *monitor* ]]
}

t_mode_confirm_needs_timer() { # no systemd-run -> refuse to enter block mode at all
	init_fw "$1"; bb apply
	printf 'systemd-run\n' >"$R/absent"
	printf '#!/bin/sh\nexit 127\n' >"$R/stubs/systemd-run"; chmod +x "$R/stubs/systemd-run"
	BB_TEST_ABSENT_FILE=$R/absent PATH="$R/stubs:$PATH" run bb mode block --confirm 30
	[ "$status" -ne 0 ]
	[[ $output == *"systemd-run is required"* ]]
	run bb mode; [[ $output == *monitor* ]]
	assert_reach 198.51.100.2                  # and nothing is being dropped
}

t_bad_apply_keeps_state() { # a failing apply must leave the running rules intact
	init_fw "$1"; bb ban 198.51.100.2; bb apply; bb mode block
	setcfg list_maxelem 4                      # shrink the cap below the list size
	seq -f '198.51.100.%g' 100 130 >"$R/l.txt"; bb list add t "$R/l.txt"; bb list update t 2>/dev/null || true
	run bb apply
	assert_blocked 198.51.100.2
	run bb status; [[ $output == *"Rules: active"* ]]
}
