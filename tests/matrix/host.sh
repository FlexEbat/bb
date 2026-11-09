#!/usr/bin/env bash
# S9.3, S9.5, S9.6 on a real host (a CI VM with systemd and Docker): install bb for real
# and check the behaviour the namespace-based suite cannot reach (S9.7, the wget path, is a suite test). Run as root. Never run on a machine you care about.
set -eu
cd "$(dirname "$0")/../.."
fail=0
ok() { printf 'ok   %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*"; fail=1; }
have() { command -v "$1" >/dev/null 2>&1; }

make install
bb install --yes --no-dpi --lang en
bb mode block

# S9.3: units run under the real systemd; the sets and rules come back after the units restart
# (a real reboot is checked by tests/matrix/reboot.sh, which needs a VM that can be restarted)
systemctl is-active --quiet bb-guard.timer && ok "guard timer is active" || bad "guard timer"
bb ban 198.51.100.77
bb doctor && ok "doctor is clean" || bad "doctor reports problems"
systemctl restart bb-firewall.service
bb status --json | jq -e '.rules == "active"' >/dev/null && ok "rules survive a restart of bb-firewall" || bad "rules after restart"

# S9.5: Docker and k3s restarts do not remove the bb rules
if systemctl cat docker.service >/dev/null 2>&1; then
	systemctl restart docker
	bb status --json | jq -e '.rules == "active"' >/dev/null && ok "rules survive a Docker restart" || bad "Docker restart"
fi
if systemctl cat k3s.service >/dev/null 2>&1; then
	systemctl restart k3s
	bb status --json | jq -e '.rules == "active"' >/dev/null && ok "rules survive a k3s restart" || bad "k3s restart"
fi

# S9.6: IPv6 traffic is blocked on a host with IPv6
if [[ -s /proc/net/if_inet6 ]] && have ip6tables && ip6tables -w -t raw -S >/dev/null 2>&1; then
	ip -6 addr add fd99::1/64 dev lo nodad 2>/dev/null || true
	bb ban fd99::/64 2>/dev/null || true
	bb apply
	if ping -6 -c1 -W1 fd99::1 >/dev/null 2>&1; then ok "loopback stays reachable (never touched)"; else bad "loopback blocked"; fi
	bb status --json | jq -e '[.sets[] | select(.name | endswith("6"))] | length > 0' >/dev/null && ok "IPv6 sets exist" || bad "no IPv6 sets"
fi

# S8.3: bb log against the real journal: the events written with the tag bb and the kernel messages of
# the LOG rules (prefix "bb: "). A banned peer in a namespace pings the host, in monitor mode.
if have ip && ip netns add bbhost 2>/dev/null; then
	ip link add bbh0 type veth peer name bbh1 && ip link set bbh1 netns bbhost
	ip addr add 198.51.100.1/24 dev bbh0 && ip link set bbh0 up
	ip -n bbhost addr add 198.51.100.2/24 dev bbh1 && ip -n bbhost link set bbh1 up && ip -n bbhost link set lo up
	bb mode monitor >/dev/null
	bb ban 198.51.100.2 >/dev/null
	ip netns exec bbhost ping -c 3 -W 1 198.51.100.1 >/dev/null 2>&1 || true
	sleep 2
	out=$(bb log -n 300 2>&1)
	if grep -qE ' kernel: bb: ' <<<"$out"; then ok "bb log shows the kernel messages of the LOG rules"; else bad "bb log: no kernel bb: line"; printf '%s\n' "$out" | tail -n 15; fi
	if grep -qE ' bb(\[[0-9]+\])?: ' <<<"$out"; then ok "bb log shows the events written with the tag bb"; else bad "bb log: no event with the tag bb"; printf '%s\n' "$out" | tail -n 15; fi
	if grep -vE ' (bb(\[[0-9]+\])?|kernel): ' <<<"$out" | grep -q .; then bad "bb log shows lines that are not bb's"; else ok "bb log shows nothing else"; fi
	ip netns del bbhost 2>/dev/null || true # this removes the veth pair as well
	ip link del bbh0 2>/dev/null || true
fi

bb uninstall --yes >/dev/null
exit $fail
