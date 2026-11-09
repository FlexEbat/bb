#!/usr/bin/env bash
# CI: the suite file by file, each with its own time limit, so that one hanging test cannot stall a job
# for hours and the log shows which file it was. Exit status 1 if anything failed or timed out.
cd "$(dirname "$0")/../.." || exit 1
rc=0
for f in tests/*.bats; do
	echo "### $f"
	timeout "${SUITE_FILE_TIMEOUT:-600}" tests/run.sh "$f"
	r=$?
	if ((r == 124)); then echo "### TIMEOUT $f"; rc=1; elif ((r != 0)); then echo "### FAILED $f"; rc=1; fi
done
exit $rc
