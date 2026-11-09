#!/usr/bin/env bash
# CI only: pushes the end of a job's log to the branch "ci-logs", so that a failure can be read
# without the Actions web page. Usage: publish-log.sh NAME [LOGFILE]
set -u
name=$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_')
log=${2:-ci.log}
[[ -s $log && -n ${GITHUB_TOKEN:-} ]] || exit 0
work=$(mktemp -d)
tail -n 700 "$log" >"$work/log.txt"
cd "$work" || exit 0
git init -q
git config user.name ci
git config user.email ci@users.noreply.github.com
git remote add origin "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
for _ in 1 2 3 4 5 6; do
	rm -rf .git/refs/heads/ci-logs
	if git fetch -q --depth 1 origin ci-logs 2>/dev/null; then git checkout -q -B ci-logs FETCH_HEAD; else git checkout -q --orphan ci-logs; fi
	mkdir -p "${GITHUB_RUN_ID:-0}"
	cp "$work/log.txt" "${GITHUB_RUN_ID:-0}/$name.log" 2>/dev/null || cp log.txt "${GITHUB_RUN_ID:-0}/$name.log"
	git add "${GITHUB_RUN_ID:-0}"
	git commit -q -m "log $name run ${GITHUB_RUN_ID:-0}" || exit 0
	git push -q origin HEAD:ci-logs 2>/dev/null && exit 0
	sleep $((RANDOM % 6 + 2))
done
exit 0
