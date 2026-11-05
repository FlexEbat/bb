#!/usr/bin/env bash
# Runs the whole suite inside a private network+mount namespace (needs root).
set -u
cd "$(dirname "$0")/.." || exit 1
if [[ ${BB_IN_NS:-} != 1 ]]; then
	exec env BB_IN_NS=1 unshare -n -m -- "$0" "$@"
fi
ip link set lo up
mkdir -p /run/netns 2>/dev/null
rm -f /run/netns/bbpeer
shellcheck -x -S warning src/bb || exit 1
bash tests/lint.sh || exit 1
bash tests/check-spec.sh || exit 1
exec bats "${@:-tests}"
