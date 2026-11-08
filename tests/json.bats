#!/usr/bin/env bats
# Slice 8: --json for status and doctor, and bb log.
load helpers

setup() {
	setup_root
	export BB_BIN_PATH=$R/sbin/bb BB_FORCE_IPV6=yes BB_SAVED_FILES=""
	mkdir -p "$R/sbin"; printf '#!/bin/sh\n' >"$R/sbin/bb"; chmod +x "$R/sbin/bb"
	printf 'ID=debian\n' >"$R/os-release"; export BB_OS_RELEASE=$R/os-release
	export BB_UFW_CONF=$R/ufw.conf BB_FIREWALLD_CONF=$R/firewalld.conf BB_NFTABLES_CONF=$R/nftables.conf
	export BB_K3S_DIR=$R/k3s BB_KUBE_MANIFEST_DIR=$R/manifests
	: >"$R/resolv.conf"; export BB_RESOLV_FILES=$R/resolv.conf
	printf '#!/bin/sh\nexit 0\n' >"$R/stubs/systemctl"
	# journalctl stand-in: records its arguments and prints a mixed stream
	cat >"$R/stubs/journalctl" <<STUB
#!/bin/sh
echo "\$*" >>"$R/jc.args"
cat <<'LOG'
2026-11-08T10:00:00+0000 host bb[41]: mode_changed mode=block
2026-11-08T10:00:01+0000 host kernel: bb: dht IN=eth0 SRC=198.51.100.7 DST=203.0.113.1
2026-11-08T10:00:02+0000 host kernel: martian source 10.0.0.1 from 10.0.0.2
2026-11-08T10:00:03+0000 host sshd[9]: Accepted publickey for root
2026-11-08T10:00:04+0000 host bb: guard_restored
2026-11-08T10:00:05+0000 host kernel: bb: list IN=eth0 SRC=198.51.100.9
LOG
STUB
	chmod +x "$R/stubs/"*
	export PATH="$R/stubs:$PATH"
}
teardown() { teardown_root; }

init() { bb __init-config --backend "$1" --ipv6 yes >/dev/null; bb apply >/dev/null; }

@test "status --json is valid JSON with stable keys on both backends (S8.1)" {
	for be in nft iptables; do
		reset_fw
		init $be
		run bb status --json
		[ "$status" -eq 0 ]
		jq -e --arg be "$be" '.backend == $be and .rules == "active" and (.version | type == "string")
			and .mode == "monitor" and .lang == "en"
			and (.sets | length > 0) and (.sets | all(.name | type == "string") )
			and (.sets | all(.entries | type == "number" or . == null))
			and (.counters | type == "array")
			and (if $be == "iptables" then (.iptables_variant | type == "string") else .iptables_variant == null end)' <<<"$output"
		jq -e '.sets[] | select(.name == "allow4")' <<<"$output" >/dev/null
	done
}

@test "status --json reports inactive rules with empty sets, and counters carry numbers (S8.1)" {
	init nft
	bb ban 198.51.100.50
	run bb status --json
	jq -e '[.sets[] | select(.name == "manual4") | .entries] == [1]' <<<"$output"
	nft delete table inet bb
	run bb status --json
	[ "$status" -eq 0 ]
	jq -e '.rules == "inactive" and .sets == [] and .counters == []' <<<"$output"
}

@test "status --json and doctor --json are the same in both languages, and nothing is translated (S8.1)" {
	init nft
	setcfg lang ru
	run bb status --json; ru_status=$output
	run bb --lang en status --json; en_status=$output
	[ "$ru_status" = "$en_status" ]
	run bb doctor --json; ru_doc=$output; ru_rc=$status
	run bb --lang en doctor --json; en_doc=$output
	[ "$ru_doc" = "$en_doc" ]
	run bb --lang en doctor
	[ "$status" -eq "$ru_rc" ]
	[[ $ru_doc != *[А-Яа-я]* ]]
}

@test "doctor --json lists checks with level, stable id and raw arguments (S8.1)" {
	init nft
	run bb doctor --json
	[ "$status" -eq 0 ]
	jq -e '.ok == true and .fail == 0 and (.warn | type == "number") and (.checks | length > 0)
		and (.checks | all(.level | IN("ok", "warn", "fail")))
		and (.checks | all((.id | test("^[a-z0-9_]+$")) and (.args | type == "array")))
		and ([.checks[] | select(.id == "backend_ok")][0].args == ["nft"])
		and ([.checks[] | select(.id == "rules_ok")] | length == 1)' <<<"$output"
	[[ $output != *"doctor"*"title"* ]]
}

@test "doctor --json keeps the exit code and the untranslated ufw state (S8.1)" {
	init nft
	printf '#!/bin/sh\ncase "$1" in status) echo "Status: active";; esac\n' >"$R/stubs/ufw"; chmod +x "$R/stubs/ufw"
	run bb doctor --json
	jq -e '[.checks[] | select(.id == "int_ufw")][0].args == ["active"]' <<<"$output"
	nft delete table inet bb
	run bb doctor --json
	[ "$status" -eq 1 ]
	jq -e '.ok == false and .fail >= 1 and ([.checks[] | select(.id == "rules_fail" and .level == "fail")] | length == 1)' <<<"$output"
}

@test "doctor --json works on an unconfigured host (S8.1)" {
	run bb doctor --json
	[ "$status" -eq 1 ]
	jq -e '[.checks[] | select(.id == "not_configured")][0].level == "fail"' <<<"$output"
}

@test "--json rejects unknown arguments" {
	init nft
	run bb status --jsno; [ "$status" -ne 0 ]
	run bb doctor --json extra; [ "$status" -ne 0 ]
}

@test "without jq a hint is printed and the exit code is non-zero, in both languages (S8.2)" {
	init nft
	printf 'jq\n' >"$R/absent"
	for l in en ru; do
		BB_TEST_ABSENT_FILE=$R/absent run bb --lang "$l" status --json
		[ "$status" -ne 0 ]
		[[ $output == *"jq"* && $output == *"apt install jq"* ]]
		BB_TEST_ABSENT_FILE=$R/absent run bb --lang "$l" doctor --json
		[ "$status" -ne 0 ]
		[[ $output == *"jq"* ]]
	done
	# the text mode needs no jq
	BB_TEST_ABSENT_FILE=$R/absent run bb status
	[ "$status" -eq 0 ]
	BB_TEST_ABSENT_FILE=$R/absent run bb doctor
	[[ $output != *"apt install jq"* ]]
}

@test "bb log merges the journal tag bb and kernel messages with the prefix bb: (S8.3)" {
	run bb log
	[ "$status" -eq 0 ]
	[[ $output == *"mode_changed mode=block"* ]]
	[[ $output == *"kernel: bb: dht IN=eth0"* ]]
	[[ $output == *"host bb: guard_restored"* ]]
	[[ $output == *"kernel: bb: list IN=eth0"* ]]
	[[ $output != *martian* && $output != *sshd* ]]
	[ "$(wc -l <<<"$output")" -eq 4 ]
	# one query: tag bb OR kernel, plain text with ISO times, bounded, not following
	grep -q -- '-t bb + _TRANSPORT=kernel' "$R/jc.args"
	grep -q -- '-o short-iso' "$R/jc.args"
	grep -q -- '-n 50' "$R/jc.args"
	refute grep -q -- ' -f' "$R/jc.args"
}

@test "bb log -f follows and -n sets the number of lines (S8.3)" {
	run bb log -f -n 7
	[ "$status" -eq 0 ]
	grep -q -- '-n 7' "$R/jc.args"
	grep -q -- ' -f' "$R/jc.args"
	run bb log --follow
	grep -q -- ' -f' "$R/jc.args"
}

@test "bb log: bad arguments and a missing journalctl are reported in the chosen language (S8.3)" {
	run bb log -n 0; [ "$status" -ne 0 ]
	run bb log -n abc; [ "$status" -ne 0 ]
	run bb log -n; [ "$status" -ne 0 ]
	run bb log --nope; [ "$status" -ne 0 ]
	printf 'journalctl\n' >"$R/absent"
	BB_TEST_ABSENT_FILE=$R/absent run bb log
	[ "$status" -ne 0 ]
	[[ $output == *"journalctl is not available"* ]]
	BB_TEST_ABSENT_FILE=$R/absent run bb --lang ru log
	[[ $output == *"journalctl недоступен"* ]]
	run bb log --help
	[[ $output == *"Usage: bb log"* ]]
	run bb --lang ru log --help
	[[ $output == *"Использование: bb log"* ]]
}
