#!/usr/bin/env bats
load helpers

FIX=$BATS_TEST_DIRNAME/fixtures/ndpid-1.7.raw

setup() {
	setup_root
	mkdir -p "$R/sbin"
	printf '#!/bin/sh\n' >"$R/sbin/bb"; chmod +x "$R/sbin/bb"
	export BB_BIN_PATH=$R/sbin/bb
	cat >"$R/stubs/logger" <<STUB
#!/bin/sh
echo "\$*" >>"$R/logger.log"
STUB
	cat >"$R/stubs/systemctl" <<STUB
#!/bin/sh
echo "systemctl \$*" >>"$R/sd.log"
exit 0
STUB
	chmod +x "$R/stubs/"*
	export PATH="$R/stubs:$PATH"
}
teardown() { teardown_root; }

# a ready system: rules and the listener's settings, as `bb install` leaves them
ready() { # backend
	bb __init-config --backend "$1" --ipv6 yes >/dev/null
	setcfg dpi yes
	bb apply >/dev/null
	[ -s "$BB_STATE_DIR/listener.conf" ]
}
# one nDPId frame: 5 digits and the JSON; the length counts the trailing newline (verified on nDPId 1.7)
frame() { printf '%05d%s\n' $((${#1} + 1)) "$1"; }
ev() { # event proto l4 sip sp dip dp [l3]
	printf '{"flow_event_name":"%s","l3_proto":"ip4","l4_proto":"%s","src_ip":"%s","src_port":%s,"dst_ip":"%s","dst_port":%s,"ndpi":{"proto":"%s"}}' "$1" "$3" "$4" "$5" "$6" "$7" "$2"
}
listen() { LC_ALL=C bb __listener; }          # stdin: the stream
send() { local j; for j in "$@"; do frame "$j"; done | listen; }
# is this exact flow in the live sets? (iptables keeps the two ends in two sets)
flow_has() { # fam proto sip sp dip dp
	if grep -q "^backend='nft'" "$BB_CONF_DIR/bb.conf"; then
		nft get element inet bb "flow$1" "{ $3 . $4 . $5 . $6 }" >/dev/null 2>&1
	else
		ipset test "bb_flow_src$1" "$3,$2:$4,$5" >/dev/null 2>&1 && ipset test "bb_flow_dst$1" "$5,$2:$6,$3" >/dev/null 2>&1
	fi
}
flow_count() { bb show flows | grep -c '^  '; }

t_real_stream() {
	ready "$1"
	run listen <"$FIX"
	[ "$status" -eq 0 ]
	flow_has 4 tcp 203.0.113.10 41000 198.51.100.20 6881        # BitTorrent over TCP / IPv4
	flow_has 4 udp 203.0.113.10 51000 198.51.100.30 6881        # DHT over UDP
	# BitTorrent over TCP / IPv6 (not where ip6tables cannot use the raw table: then only IPv4 is handled)
	if [[ $1 != iptables ]] || ip6tables -w -t raw -S >/dev/null 2>&1; then
		flow_has 6 tcp 2001:db8::10 42000 2001:db8:1::20 6881
	fi
	refute flow_has 4 tcp 203.0.113.10 43000 198.51.100.40 80   # the HTTP flow of the same capture
}

t_event_selection() {
	ready "$1"
	send "$(ev new BitTorrent tcp 203.0.113.1 1001 198.51.100.1 6881)" \
	     "$(ev guessed BitTorrent tcp 203.0.113.1 1002 198.51.100.1 6881)" \
	     "$(ev idle BitTorrent tcp 203.0.113.1 1003 198.51.100.1 6881)" \
	     "$(ev end BitTorrent tcp 203.0.113.1 1004 198.51.100.1 6881)" \
	     "$(ev detected HTTP tcp 203.0.113.1 1005 198.51.100.1 80)" \
	     "$(ev detected TLS tcp 203.0.113.1 1006 198.51.100.1 443)" \
	     "$(ev detected BitTorrent tcp 203.0.113.1 1010 198.51.100.1 6881)" \
	     "$(ev detection-update uTP.BitTorrent udp 203.0.113.1 1011 198.51.100.1 6881)" \
	     "$(ev detected bittorrent tcp 203.0.113.1 1012 198.51.100.1 6881)"
	flow_has 4 tcp 203.0.113.1 1010 198.51.100.1 6881
	flow_has 4 udp 203.0.113.1 1011 198.51.100.1 6881
	flow_has 4 tcp 203.0.113.1 1012 198.51.100.1 6881
	for p in 1001 1002 1003 1004 1005 1006; do refute flow_has 4 tcp 203.0.113.1 $p 198.51.100.1 6881; done
	[ "$(flow_count)" -ge 3 ]
}

t_hostile() {
	ready "$1"
	local good; good=$(ev detected BitTorrent tcp 203.0.113.7 7000 198.51.100.7 6881)
	cd "$R"
	send "$(ev detected BitTorrent tcp '1.2.3.4; touch PWNED' 1 198.51.100.7 6881)" \
	     "$(ev detected BitTorrent tcp '$(touch PWNED)' 1 198.51.100.7 6881)" \
	     "$(ev detected BitTorrent tcp '`touch PWNED`' 1 198.51.100.7 6881)" \
	     "$(ev detected BitTorrent tcp '1.2.3.4
touch PWNED' 1 198.51.100.7 6881)" \
	     "$(ev detected BitTorrent tcp 999.1.1.1 1 198.51.100.7 6881)" \
	     "$(ev detected BitTorrent tcp 1.2.3 1 198.51.100.7 6881)" \
	     "$(ev detected BitTorrent tcp ::g 1 198.51.100.7 6881)" \
	     "$(ev detected BitTorrent tcp 203.0.113.9 0 198.51.100.7 6881)" \
	     "$(ev detected BitTorrent tcp 203.0.113.9 65536 198.51.100.7 6881)" \
	     "$(ev detected BitTorrent tcp 203.0.113.9 '"1234"' 198.51.100.7 6881)" \
	     "$(ev detected BitTorrent tcp 203.0.113.9 1234.5 198.51.100.7 6881)" \
	     "$(ev detected BitTorrent tcp 203.0.113.9 -1 198.51.100.7 6881)" \
	     "$(ev detected BitTorrent tcp 203.0.113.9 null 198.51.100.7 6881)" \
	     "$(ev detected BitTorrent tcp 203.0.113.9 1e30 198.51.100.7 6881)" \
	     "$(ev detected BitTorrent icmp 203.0.113.9 1234 198.51.100.7 6881)" \
	     "$(ev detected BitTorrent tcp 203.0.113.9 1234 2001:db8::7 6881)" \
	     '{"flow_event_name":"detected","l4_proto":"tcp","src_ip":"203.0.113.9","src_port":1,"dst_port":2,"ndpi":{"proto":"BitTorrent"}}' \
	     '{"flow_event_name":"detected","l4_proto":"tcp","src_ip":["1.2.3.4"],"dst_ip":{"a":1},"src_port":1,"dst_port":2,"ndpi":{"proto":"BitTorrent"}}' \
	     '{"flow_event_name":"detected","l4_proto":"tcp","src_ip":"203.0.113.9","dst_ip":"198.51.100.7","src_port":1,"dst_port":2,"ndpi":{"proto":["BitTorrent"]}}' \
	     '{"flow_event_name":"detected","l4_proto":"tcp","src_ip":"203.0.113.9","dst_ip":"198.51.100.7","src_port":1,"dst_port":2,"ndpi":"BitTorrent"}' \
	     '[1,2,3]' '"just a string"' 'null' '12345' \
	     "$good"
	[ ! -e "$R/PWNED" ] && [ ! -e PWNED ]
	flow_has 4 tcp 203.0.113.7 7000 198.51.100.7 6881          # the one good event still went through
	[ "$(flow_count)" -le 2 ]                                   # ...and nothing else did
}

t_protocol_errors() {
	ready "$1"
	local a b; a=$(ev detected BitTorrent tcp 203.0.113.20 2001 198.51.100.20 6881); b=$(ev detected BitTorrent tcp 203.0.113.20 2002 198.51.100.20 6881)
	# 1. a non-numeric header ends the connection: what came before counts, what follows does not
	{ frame "$a"; printf 'GARBAGE'; frame "$b"; } | listen || true
	flow_has 4 tcp 203.0.113.20 2001 198.51.100.20 6881
	refute flow_has 4 tcp 203.0.113.20 2002 198.51.100.20 6881
	grep -q 'listener_frame_error reason=header' "$R/logger.log"
	# 2. a zero or over-sized length
	: >"$R/logger.log"
	{ printf '00000'; frame "$b"; } | listen || true
	grep -q 'reason=length' "$R/logger.log"
	sed -i "s/^max_event_size=.*/max_event_size='100'/" "$BB_STATE_DIR/listener.conf"
	: >"$R/logger.log"
	{ printf '00200'; head -c 200 /dev/zero | tr '\0' 'x'; } | listen || true
	grep -q 'reason=length' "$R/logger.log"
	refute flow_has 4 tcp 203.0.113.20 2002 198.51.100.20 6881
	# 3. a frame cut short at EOF
	sed -i "s/^max_event_size=.*/max_event_size='1048576'/" "$BB_STATE_DIR/listener.conf"
	: >"$R/logger.log"
	{ printf '%05d' 500; printf '%s' "$b"; } | listen || true
	grep -q 'reason=truncated' "$R/logger.log"
	# 4. NUL bytes inside a frame make its length wrong
	: >"$R/logger.log"
	{ printf '%05d' $((${#b} + 1)); printf '%s\0\n' "${b:1}"; } | listen || true
	refute flow_has 4 tcp 203.0.113.20 2002 198.51.100.20 6881
	# 5. an empty stream and a half header are harmless
	run listen </dev/null; [ "$status" -eq 0 ]
	{ printf '000'; } | listen || true
}

t_corrupt_json_skipped() {
	ready "$1"
	send '{"flow_event_name":"detected", broken' \
	     "$(ev detected BitTorrent tcp 203.0.113.30 3001 198.51.100.30 6881)"
	flow_has 4 tcp 203.0.113.30 3001 198.51.100.30 6881
}

t_filtering() {
	ready "$1"
	bb allow 198.51.100.77 >/dev/null
	local ok; ok=$(ev detected BitTorrent tcp 203.0.113.40 4001 198.51.100.40 6881)
	send "$(ev detected BitTorrent tcp 10.1.1.1 4002 198.51.100.40 6881)" \
	     "$(ev detected BitTorrent tcp 203.0.113.40 4003 192.168.5.5 6881)" \
	     "$(ev detected BitTorrent tcp 127.0.0.1 4004 198.51.100.40 6881)" \
	     "$(ev detected BitTorrent tcp 169.254.1.1 4005 198.51.100.40 6881)" \
	     "$(ev detected BitTorrent tcp 100.64.0.9 4006 198.51.100.40 6881)" \
	     "$(ev detected BitTorrent tcp fc00::1 4007 2001:db8::1 6881)" \
	     "$(ev detected BitTorrent tcp fe80::1 4008 2001:db8::1 6881)" \
	     "$(ev detected BitTorrent tcp ::ffff:1.2.3.4 4009 2001:db8::1 6881)" \
	     "$ok"
	# the allowlisted address is looked up once per batch, so each side gets a batch of its own
	send "$(ev detected BitTorrent tcp 203.0.113.40 4010 198.51.100.77 6881)"
	send "$(ev detected BitTorrent tcp 198.51.100.77 4011 203.0.113.40 6881)"
	flow_has 4 tcp 203.0.113.40 4001 198.51.100.40 6881
	# every excluded flow is checked on its own: a source-side and a destination-side miss are different bugs
	refute flow_has 4 tcp 10.1.1.1 4002 198.51.100.40 6881
	refute flow_has 4 tcp 203.0.113.40 4003 192.168.5.5 6881
	refute flow_has 4 tcp 127.0.0.1 4004 198.51.100.40 6881
	refute flow_has 4 tcp 169.254.1.1 4005 198.51.100.40 6881
	refute flow_has 4 tcp 100.64.0.9 4006 198.51.100.40 6881
	refute flow_has 6 tcp fc00::1 4007 2001:db8::1 6881
	refute flow_has 6 tcp fe80::1 4008 2001:db8::1 6881
	refute flow_has 4 tcp 203.0.113.40 4010 198.51.100.77 6881      # allowlisted destination
	refute flow_has 4 tcp 198.51.100.77 4011 203.0.113.40 6881      # allowlisted source
	bb allow 198.51.100.77 --rm >/dev/null                      # the allowlist is read live, not cached
	send "$(ev detected BitTorrent tcp 203.0.113.40 4012 198.51.100.77 6881)"
	flow_has 4 tcp 203.0.113.40 4012 198.51.100.77 6881
}

t_dedup() {
	ready "$1"
	local e; e=$(ev detected BitTorrent tcp 203.0.113.50 5001 198.51.100.50 6881)
	: >"$R/logger.log"
	send "$e" "$e" "$e" "$e" "$e"
	flow_has 4 tcp 203.0.113.50 5001 198.51.100.50 6881
	grep -q 'flows_added count=1$' "$R/logger.log"              # five events, one flow added
	[ "$(grep -c 'flows_added' "$R/logger.log")" -eq 1 ]
}

t_rate_limit() {
	ready "$1"
	sed -i "s/^flow_rate_limit=.*/flow_rate_limit='5'/" "$BB_STATE_DIR/listener.conf"
	local -a evs=()
	for i in $(seq 1 20); do evs+=("$(ev detected BitTorrent tcp 203.0.113.60 $((6000 + i)) 198.51.100.60 6881)"); done
	: >"$R/logger.log"
	send "${evs[@]}"
	[ "$(flow_count)" -ge 5 ]
	refute flow_has 4 tcp 203.0.113.60 6020 198.51.100.60 6881  # past the limit: dropped
	[ "$(grep -c '^rate_limit ' "$BB_STATE_DIR/listener/events")" -eq 1 ]   # one note per minute
	grep -q 'rate_limit limit=5' "$R/logger.log"
	# the root side turns the note into an event, and only that exact line format is honoured
	: >"$R/logger.log"
	bb guard >/dev/null
	grep -q '^rate_limit' "$R/logger.log" || grep -q 'rate_limit' "$R/logger.log"
	[ ! -s "$BB_STATE_DIR/listener/events" ]
	printf 'rate_limit abc\nevil; rm -rf /\nrate_limit  1\n' >"$BB_STATE_DIR/listener/events"
	: >"$R/logger.log"
	bb guard >/dev/null
	refute grep -q 'rate_limit' "$R/logger.log"
}

t_save_restore() {
	ready "$1"
	send "$(ev detected BitTorrent tcp 203.0.113.70 7001 198.51.100.70 6881)"
	flow_has 4 tcp 203.0.113.70 7001 198.51.100.70 6881
	bb __save-flows
	grep -q '^# saved ' "$BB_STATE_DIR/flows.save"
	[ "$(grep -c "^$( [ "$1" = nft ] && echo nft || echo ipt)	" "$BB_STATE_DIR/flows.save")" -ge 1 ]
	bb __remove                                                 # a "reboot": all kernel state is gone
	refute flow_has 4 tcp 203.0.113.70 7001 198.51.100.70 6881 2>/dev/null
	sleep 2
	bb apply >/dev/null
	flow_has 4 tcp 203.0.113.70 7001 198.51.100.70 6881
	run bb show flows
	left=$(awk '/203.0.113.70/ { print $NF }' <<<"$output" | tr -d 's')
	[ "${left:-0}" -gt 0 ] && [ "${left:-0}" -lt 86400 ]       # the time that passed is taken off the TTL
	bb apply >/dev/null                                         # a later apply does not resurrect or duplicate
	[ "$(flow_count)" -ge 1 ]
}

t_restore_expired() {
	ready "$1"
	setcfg flow_ttl 2s; bb apply >/dev/null
	sed -i "s/^flow_ttl=.*/flow_ttl='2s'/" "$BB_STATE_DIR/listener.conf"
	send "$(ev detected BitTorrent tcp 203.0.113.71 7101 198.51.100.71 6881)"
	bb __save-flows
	bb __remove
	sleep 4
	bb apply >/dev/null
	refute flow_has 4 tcp 203.0.113.71 7101 198.51.100.71 6881 # its TTL ran out while the host was down
}

t_show() {
	ready "$1"
	run bb show flows
	[[ $output == *"There are no dynamic flows."* ]]
	send "$(ev detected BitTorrent tcp 203.0.113.80 8001 198.51.100.80 6881)"
	run bb show flows
	[[ $output == *"Dynamic flows"* && $output == *"203.0.113.80"* && $output == *"198.51.100.80"* ]]
	run bb --lang ru show flows
	[[ $output == *"Динамические потоки"* ]]
	run bb show bogus; [ "$status" -ne 0 ]
}

@test "nft: the real nDPId 1.7 stream yields the BitTorrent flows (TCP v4/v6, UDP) and not the HTTP one" { t_real_stream nft; }
@test "iptables: the real nDPId 1.7 stream yields the BitTorrent flows (TCP v4/v6, UDP) and not the HTTP one" { t_real_stream iptables; }
@test "nft: only detected and detection-update BitTorrent events become flows" { t_event_selection nft; }
@test "iptables: only detected and detection-update BitTorrent events become flows" { t_event_selection iptables; }
@test "nft: hostile or malformed fields never reach a command" { t_hostile nft; }
@test "iptables: hostile or malformed fields never reach a command" { t_hostile iptables; }
@test "nft: invalid, truncated and oversized frames end the connection safely" { t_protocol_errors nft; }
@test "iptables: invalid, truncated and oversized frames end the connection safely" { t_protocol_errors iptables; }
@test "nft: corrupt JSON lines are skipped and the stream goes on" { t_corrupt_json_skipped nft; }
@test "iptables: corrupt JSON lines are skipped and the stream goes on" { t_corrupt_json_skipped iptables; }
@test "nft: private, special and allowlisted addresses never enter flow" { t_filtering nft; }
@test "iptables: private, special and allowlisted addresses never enter flow" { t_filtering iptables; }
@test "nft: repeated events are deduplicated" { t_dedup nft; }
@test "iptables: repeated events are deduplicated" { t_dedup iptables; }
@test "nft: exceeding the rate limit pauses the listener and raises rate_limit once" { t_rate_limit nft; }
@test "iptables: exceeding the rate limit pauses the listener and raises rate_limit once" { t_rate_limit iptables; }
@test "nft: dynamic flows survive a restart with what is left of their TTL" { t_save_restore nft; }
@test "iptables: dynamic flows survive a restart with what is left of their TTL" { t_save_restore iptables; }
@test "nft: a flow whose TTL ran out while the host was down is not restored" { t_restore_expired nft; }
@test "iptables: a flow whose TTL ran out while the host was down is not restored" { t_restore_expired iptables; }
@test "nft: bb show flows lists the flows, says when there are none, and is localized" { t_show nft; }
@test "iptables: bb show flows lists the flows, says when there are none, and is localized" { t_show iptables; }

# S7.9: the deduplication memory is bounded: when it is full it is cleared, and an old flow is seen as new again
t_dedup_bound() {
	ready "$1"
	local first evs=() i
	first=$(ev detected BitTorrent tcp 203.0.113.70 7000 198.51.100.70 6881)
	evs+=("$first")
	for i in $(seq 1 10); do evs+=("$(ev detected BitTorrent tcp 203.0.113.70 $((7000 + i)) 198.51.100.70 6881)"); done
	evs+=("$first")
	: >"$R/logger.log"
	BB_SEEN_MAX=10 send "${evs[@]}"
	grep -q 'flows_added count=12$' "$R/logger.log"          # the first flow came back after the memory was cleared
	# with the real bound the same events are deduplicated
	: >"$R/logger.log"
	send "${evs[@]}"
	grep -q 'flows_added count=11$' "$R/logger.log"
}
@test "nft: the deduplication memory is bounded and cleared when full" { t_dedup_bound nft; }
@test "iptables: the deduplication memory is bounded and cleared when full" { t_dedup_bound iptables; }
