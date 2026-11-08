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
if [[ -e /proc/net/if_inet6 ]] && have ip6tables; then
	ip -6 addr add fd99::1/64 dev lo nodad 2>/dev/null || true
	bb ban fd99::/64 2>/dev/null || true
	bb apply
	if ping -6 -c1 -W1 fd99::1 >/dev/null 2>&1; then ok "loopback stays reachable (never touched)"; else bad "loopback blocked"; fi
	bb status --json | jq -e '[.sets[] | select(.name | endswith("6"))] | length > 0' >/dev/null && ok "IPv6 sets exist" || bad "no IPv6 sets"
fi

bb uninstall --yes >/dev/null
exit $fail
