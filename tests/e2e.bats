#!/usr/bin/env bats
# End to end with the REAL nDPId: live capture -> unix socket -> listener -> kernel sets -> blocked.
# Needs a built nDPId (BB_REAL_NDPID=/path/to/nDPId) and socat, which stands in for systemd's
# socket activation; otherwise the tests skip themselves.
load helpers

setup() {
	[ -x "${BB_REAL_NDPID:-/nonexistent}" ] || skip "BB_REAL_NDPID is not set to a built nDPId"
	command -v socat >/dev/null || skip "socat is not installed"
	setup_root
	topo_up
	export BB_UNIT_DIR=$R/units
	useradd --system --user-group --no-create-home --shell /usr/sbin/nologin bb-ndpid 2>/dev/null || true
	cat >"$R/stubs/logger" <<STUB
#!/bin/sh
echo "\$*" >>"$R/logger.log"
STUB
	chmod +x "$R/stubs/"*; export PATH="$R/stubs:$PATH"
	bb __init-config --backend "${E2E_BACKEND:-nft}" --ipv6 yes >/dev/null
	setcfg dpi yes; setcfg iface bbv0
	bb apply >/dev/null
	# what bb-listener.socket does: one listener per connection
	printf '#!/bin/sh\necho conn >>"%s/conn.log"\nexec "%s" __listener\n' "$R" "$BB" >"$R/listener-wrap"
	chmod +x "$R/listener-wrap"
}
teardown() {
	[ -n "${R:-}" ] || return 0
	for f in "$R"/*.pid; do [ -e "$f" ] && kill "$(cat "$f")" 2>/dev/null; done
	pkill -x nDPId 2>/dev/null; pkill -x socat 2>/dev/null
	userdel bb-ndpid 2>/dev/null || true; groupdel bb-ndpid 2>/dev/null || true
	teardown_root
}

# is the flow of the test connection in the live sets? (either backend)
flow_live() {
	if [ "${E2E_BACKEND:-nft}" = nft ]; then
		nft get element inet bb flow4 "{ 198.51.100.1 . 45678 . 198.51.100.2 . 6881 }" >/dev/null 2>&1
	else
		ipset test bb_flow_src4 198.51.100.1,tcp:45678,198.51.100.2 >/dev/null 2>&1 && ipset test bb_flow_dst4 198.51.100.2,tcp:6881,198.51.100.1 >/dev/null 2>&1
	fi
}

HS='\023BitTorrent protocol\000\000\000\000\000\020\000\005AAAAAAAAAAAAAAAAAAAABBBBBBBBBBBBBBBBBBBB'

# Starts the stack the way the units do: the socket belongs to bb-ndpid, and nDPId runs as bb-ndpid
# with only CAP_NET_RAW and CAP_NET_ADMIN, using the command line that bb puts into its unit.
start_stack() {
	chmod 755 "$R"
	export BB_NDPID_BIN=$BB_REAL_NDPID
	cmd=$(bb __unit bb-ndpid.service | sed -n 's/^ExecStart=//p')
	cmd=${cmd//\/run\/bb\/ndpid.sock/$R\/ndpid.sock}
	socat UNIX-LISTEN:"$R/ndpid.sock",fork,mode=600,user=bb-ndpid,backlog=64 EXEC:"$R/listener-wrap" >"$R/socat.log" 2>&1 3>&- &
	echo $! >"$R/socat.pid"
	sleep 0.5
	# shellcheck disable=SC2086
	eval "setpriv --reuid=bb-ndpid --regid=bb-ndpid --clear-groups --inh-caps=-all,+net_raw,+net_admin --ambient-caps=+net_raw,+net_admin --bounding-set=-all,+net_raw,+net_admin $cmd -l" >"$R/ndpid.log" 2>&1 3>&- &
	echo $! >"$R/ndpid.pid"
	sleep 3
	echo "nDPId command: $cmd"
	pgrep -x nDPId >/dev/null || { cat "$R/ndpid.log"; return 1; }
}

@test "real nDPId: a live BitTorrent connection is detected, its flow is added and the connection is cut" {
	start_stack
	# the "tracker" answers with a handshake and logs what it receives (a script: socat would eat the backslashes)
	printf '#!/bin/sh\nprintf '"'"'%s'"'"'\ncat >>"%s/srv.out"\n' "$HS" "$R" >"$R/peer-handler"; chmod 755 "$R/peer-handler"
	ip netns exec bbpeer socat TCP-LISTEN:6881,reuseaddr,fork EXEC:"$R/peer-handler" >/dev/null 2>&1 3>&- &
	echo $! >"$R/peer.pid"
	sleep 0.5
	{ printf "$HS"; sleep 14; printf 'LATE-DATA'; sleep 2; } | nc -s 198.51.100.1 -p 45678 -w 20 198.51.100.2 6881 >/dev/null 2>&1 3>&- &
	echo $! >"$R/client.pid"
	# wait until the listener has put the flow into the live set (detection + one batch interval)
	found=0
	for i in $(seq 1 24); do
		if flow_live; then found=1; break; fi
		sleep 0.5
	done
	echo "found=$found; connections to the socket: $(wc -l <"$R/conn.log" 2>/dev/null)"
	[ "$found" -eq 1 ]
	bb mode block >/dev/null                                    # from now on the flow rule drops
	# the client sends LATE-DATA 14 s after it started; wait until the rule has dropped packets of this
	# connection (TCP keeps retransmitting them), so that "never arrived" cannot hold vacuously
	dropped=0
	for i in $(seq 1 40); do
		if bb status | grep -qE 'flow[[:space:]]+packets[[:space:]]+[1-9]'; then dropped=1; break; fi
		sleep 0.5
	done
	[ "$dropped" -eq 1 ]
	sleep 1
	grep -q 'BitTorrent protocol' "$R/srv.out"                  # the handshake went through before the flow existed
	refute grep -q 'LATE-DATA' "$R/srv.out"                     # ...and what came after was dropped
}

@test "real nDPId: ordinary traffic produces no flow" {
	start_stack
	ip netns exec bbpeer socat TCP-LISTEN:8080,reuseaddr,fork SYSTEM:"printf 'HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nhi'" >/dev/null 2>&1 3>&- &
	echo $! >"$R/peer.pid"
	sleep 0.5
	for i in 1 2 3; do printf 'GET / HTTP/1.1\r\nHost: example.org\r\n\r\n' | nc -s 198.51.100.1 -p $((46000 + i)) -w 2 198.51.100.2 8080 >/dev/null 2>&1; done
	sleep 6
	run bb show flows
	[[ $output == *"There are no dynamic flows."* ]]
}
