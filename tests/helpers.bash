# Shared helpers for the bats suites. Everything runs inside a throwaway
# network+mount namespace created by tests/run.sh, so real nft/ipset/iptables
# state can be created and destroyed freely.
REPO=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
BB=$REPO/src/bb

setup_root() {
	R=$(mktemp -d)
	export BB_TESTING=1 BB_CONF_DIR=$R/etc BB_STATE_DIR=$R/var BB_BACKUP_DIR=$R/bak
	export BB_LOCK_FILE=$R/lock BB_SHARE_DIR=$R/share LANG=C.UTF-8 LC_ALL=C.UTF-8
	mkdir -p "$R/share" "$R/stubs"
	ln -s "$REPO/lang" "$R/share/lang"
	ln -s "$REPO/src/net.awk" "$R/share/net.awk"
	unset BB_LANG
}

bb() { "$BB" "$@"; }

# Set KEY='value' in bb.conf.
setcfg() { sed -i "s|^$1=.*|$1='$2'|" "$BB_CONF_DIR/bb.conf"; }

reset_fw() {
	nft flush ruleset 2>/dev/null
	iptables -t raw -F 2>/dev/null; iptables -t raw -X 2>/dev/null
	ip6tables -t raw -F 2>/dev/null; ip6tables -t raw -X 2>/dev/null
	ipset flush 2>/dev/null; ipset destroy 2>/dev/null
	return 0
}

teardown_root() {
	pkill -f 'nc .*-l' 2>/dev/null
	reset_fw
	ip netns del bbpeer 2>/dev/null
	ip link del bbv0 2>/dev/null
	rm -rf "$R"
	return 0
}

# Two namespaces joined by a veth pair: here 198.51.100.1, peer 198.51.100.2
# (TEST-NET-2, i.e. not private, so list sanitizing does not remove it).
topo_up() {
	ip netns add bbpeer
	ip link add bbv0 type veth peer name bbv1
	ip link set bbv1 netns bbpeer
	ip addr add 198.51.100.1/24 dev bbv0
	ip link set bbv0 up
	ip -n bbpeer addr add 198.51.100.2/24 dev bbv1
	ip -n bbpeer link set bbv1 up
	ip -n bbpeer link set lo up
	ip link set lo up
	ip addr add fd99::1/64 dev bbv0 nodad 2>/dev/null || true
	ip -n bbpeer addr add fd99::2/64 dev bbv1 nodad 2>/dev/null || true
	return 0
}

reach() { ping -c1 -W1 "$1" >/dev/null 2>&1; }
assert_reach() { reach "$1" || { echo "expected $1 to be reachable"; return 1; }; }
assert_blocked() { if reach "$1"; then echo "expected $1 to be blocked"; return 1; fi; }

# udp_delivered PORT: does a datagram to the peer reach it?
udp_delivered() {
	rm -f "$R/udp.out"
	ip netns exec bbpeer sh -c "nc -u -l $1 >'$R/udp.out'" &
	local pid=$!
	sleep 0.3
	printf 'hello\n' | nc -u -w1 198.51.100.2 "$1" 2>/dev/null
	sleep 0.4
	kill "$pid" 2>/dev/null; pkill -f "nc -u -l" 2>/dev/null; wait "$pid" 2>/dev/null || true
	[[ -s $R/udp.out ]]
}

tcp_listen() { ip netns exec bbpeer nc -l -k "$1" >/dev/null 2>&1 & sleep 0.3; }
tcp_ok() { nc -z -w2 -s 198.51.100.1 -p "$1" 198.51.100.2 "$2" 2>/dev/null; }

status_count() { bb status | awk -v k="$1" '$1 == k { print $2 }'; }
