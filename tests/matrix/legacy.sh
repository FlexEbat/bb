#!/usr/bin/env bash
# S9.2: switch the container to the legacy iptables variant, check bb sees it, run the suite.
set -eu
cd "$(dirname "$0")/../.."
for b in iptables ip6tables; do update-alternatives --set "$b" "/usr/sbin/$b-legacy"; done
iptables --version | grep -q legacy
exec tests/run.sh
