#!/usr/bin/env bats
load helpers

setup() { setup_root; }
teardown() { teardown_root; }

@test "norm: networks are canonicalized (host bits cleared, /32 dropped, v6 compressed)" {
	bb __init-config --backend nft --ipv6 yes
	bb ban 198.51.100.77/24
	bb ban 203.0.113.5/32
	bb ban 2001:0DB8:0:0:0:0:0:5
	run cat "$BB_CONF_DIR/manual.list"
	[[ $output == *"198.51.100.0/24 0"* ]]
	[[ $output == *"203.0.113.5 0"* ]]
	[[ $output == *"2001:db8::5 0"* ]]
}

@test "norm: invalid and too-broad entries are rejected" {
	bb __init-config --backend nft
	for e in 0.0.0.0/0 1.2.3 256.1.1.1 01.2.3.4 ::/0 1::2::3 "1.2.3.4 5.6.7.8" evil.example.com '1.2.3.4;ls'; do
		run bb ban "$e"
		[ "$status" -ne 0 ]
	done
	[ ! -s "$BB_CONF_DIR/manual.list" ]
}

@test "ban list: permanent and timed bans, expired ones are left out" {
	bb __init-config --backend nft
	run bb ban list
	[ "$status" -eq 0 ]; [[ $output == "No manual bans." ]]
	bb ban 198.51.100.9
	bb ban 203.0.113.0/24 --ttl 2d
	bb ban 2001:db8::7 --ttl 30m
	printf '192.0.2.99 %s\n' "$(($(date +%s) - 10))" >>"$BB_CONF_DIR/manual.list"   # expired
	run bb ban list
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 3 ]
	[[ $output == *$'198.51.100.9\tpermanent'* ]]
	[[ $output == *$'203.0.113.0/24\texpires in 1d 23h'* || $output == *$'203.0.113.0/24\texpires in 2d 0h'* ]]
	[[ $output == *$'2001:db8::7\texpires in 29m'* || $output == *$'2001:db8::7\texpires in 30m'* ]]
	[[ $output != *192.0.2.99* ]]
	run bb ban list extra
	[ "$status" -ne 0 ]
}

@test "allow list: manual entries and the generated ones with their source" {
	bb __init-config --backend nft
	run bb allow list
	[ "$status" -eq 0 ]; [[ $output == "The allowlist is empty." ]]
	bb allow 192.168.1.0/24
	bb allow 2001:db8:1::/48
	mkdir -p "$BB_STATE_DIR"
	printf '10.9.8.7\n' >"$BB_STATE_DIR/integrations.allow"
	printf '149.154.167.99\n' >"$BB_STATE_DIR/notify.allow"
	run bb allow list
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 4 ]
	[[ $output == *$'192.168.1.0/24\tmanual'* ]]
	[[ $output == *$'2001:db8:1::/48\tmanual'* ]]
	[[ $output == *$'149.154.167.99\tnotifications'* ]]
	[[ $output == *$'10.9.8.7\tintegrations'* ]]
	run bb allow list extra
	[ "$status" -ne 0 ]
}

@test "ban/unban/allow edit the source files; ban is idempotent" {
	bb __init-config --backend nft
	bb ban 198.51.100.9
	bb ban 198.51.100.9
	[ "$(wc -l <"$BB_CONF_DIR/manual.list")" -eq 1 ]
	bb unban 198.51.100.9
	[ ! -s "$BB_CONF_DIR/manual.list" ]
	run bb unban 198.51.100.9
	[ "$status" -ne 0 ]
	bb allow 192.168.1.0/24
	grep -qx '192.168.1.0/24' "$BB_CONF_DIR/allow.list"
	bb allow 192.168.1.0/24 --rm
	[ ! -s "$BB_CONF_DIR/allow.list" ]
	run bb allow 192.168.1.0/24 --rm
	[ "$status" -ne 0 ]
}

@test "ban --ttl validates durations and stores an expiry" {
	bb __init-config --backend nft
	run bb ban 198.51.100.9 --ttl 5x
	[ "$status" -ne 0 ]
	run bb ban 198.51.100.9 --ttl 0
	[ "$status" -ne 0 ]
	bb ban 198.51.100.9 --ttl 7d
	exp=$(awk '{ print $2 }' "$BB_CONF_DIR/manual.list")
	now=$(date +%s)
	[ "$exp" -gt $((now + 7 * 86400 - 5)) ]
	[ "$exp" -le $((now + 7 * 86400 + 5)) ]
}

@test "config: strict parser ignores junk lines and invalid values, never executes" {
	bb __init-config --backend nft
	printf 'mode='"'"'block'"'"'\n$(touch %s/pwned)\nflow_ttl='"'"'abc'"'"'\nmin_list_ratio='"'"'7'"'"'\n' >>"$BB_CONF_DIR/bb.conf"
	run bb mode
	[ ! -e "$R/pwned" ]
	[[ $output == *"block"* ]]
	[[ $output == *"flow_ttl"* ]]
}

@test "config file is mode 0600 and written atomically" {
	bb __init-config --backend nft
	[ "$(stat -c %a "$BB_CONF_DIR/bb.conf")" = 600 ]
	[ ! -e "$BB_CONF_DIR/bb.conf.new" ]
}

@test "commands refuse to run unconfigured" {
	run bb apply
	[ "$status" -ne 0 ]
	[[ $output == *"not configured"* ]]
}

@test "unknown command and unknown option fail with non-zero exit" {
	run bb frobnicate
	[ "$status" -ne 0 ]
	bb __init-config --backend nft
	run bb ban --nope 1.2.3.4
	[ "$status" -ne 0 ]
}

@test "every command answers --help" {
	for c in apply guard status mode ban unban allow lang list; do
		run bb "$c" --help
		[ "$status" -eq 0 ]
		[[ $output == Usage:* ]]
	done
	run bb --help
	[ "$status" -eq 0 ]
}

@test "language: precedence flag > BB_LANG > bb.conf > en" {
	bb __init-config --backend nft
	run bb mode
	[[ $output == "Current mode:"* ]]
	bb lang ru
	grep -q "^lang='ru'" "$BB_CONF_DIR/bb.conf"
	run bb mode
	[[ $output == "Текущий режим:"* ]]
	BB_LANG=en run bb mode
	[[ $output == "Current mode:"* ]]
	BB_LANG=en run bb --lang ru mode
	[[ $output == "Текущий режим:"* ]]
	run bb --lang xx mode
	[ "$status" -ne 0 ]
}

@test "language: Russian help and errors contain no English leftovers" {
	bb __init-config --backend nft
	run bb --lang ru ban --help
	[[ $output == "Использование:"* ]]
	run bb --lang ru ban 0.0.0.0/0
	[ "$status" -ne 0 ]
	[[ $output == "ошибка:"* ]]
	[[ $output != *"not a valid"* ]]
}

@test "language: Russian on a non-UTF-8 locale warns and falls back to English" {
	bb __init-config --backend nft
	LC_ALL=C LANG=C run bb --lang ru mode
	[ "$status" -eq 0 ]
	[[ $output == *"UTF-8"* ]]
	[[ $output == *"Current mode:"* ]]
	[[ $output != *"Текущий"* ]]
}

@test "language: --json-like machine output and exit codes do not depend on language" {
	bb __init-config --backend nft
	run bb ban 0.0.0.0/0; en=$status
	run bb --lang ru ban 0.0.0.0/0; ru=$status
	[ "$en" -eq "$ru" ]
}

@test "lists: only https sources, valid names, sha256 format" {
	bb __init-config --backend nft
	run bb list add x http://example.com/l.txt
	[ "$status" -ne 0 ]
	run bb list add 'Bad Name' https://example.com/l.txt
	[ "$status" -ne 0 ]
	run bb list add dht https://example.com/l.txt
	[ "$status" -ne 0 ]
	run bb list add x https://example.com/l.txt --sha256 nothex
	[ "$status" -ne 0 ]
	run bb list add x "https://example.com/it's.txt"
	[ "$status" -ne 0 ]
	bb list add x https://example.com/l.txt
	[ -s "$BB_CONF_DIR/lists.d/x.conf" ]
	bb list rm x
	[ ! -e "$BB_CONF_DIR/lists.d/x.conf" ]
}

@test "lists: without curl the download goes through wget with --https-only (S9.7)" {
	bb __init-config --backend nft
	cat >"$R/stubs/wget" <<STUB
#!/bin/sh
echo "\$*" >>"$R/wget.args"
printf '198.51.100.30\n198.51.100.31\n10.0.0.1\n'
STUB
	chmod +x "$R/stubs/wget"
	printf 'curl\n' >"$R/absent"
	export BB_TEST_ABSENT_FILE=$R/absent PATH="$R/stubs:$PATH"
	bb list add w https://example.com/w.txt
	bb list update w
	grep -q -- '--https-only' "$R/wget.args"
	run cat "$BB_STATE_DIR/lists/w.list"
	[[ $output == *198.51.100.30* && $output != *10.0.0.1* ]]
}

@test "lists: https download goes through curl with https-only protocol flags" {
	bb __init-config --backend nft
	cat >"$R/stubs/curl" <<STUB
#!/bin/sh
echo "\$*" >>"$R/curl.args"
printf '198.51.100.20\n198.51.100.21\nudp://tracker.example:6969/announce\n10.0.0.1\n'
STUB
	chmod +x "$R/stubs/curl"
	PATH="$R/stubs:$PATH" bb list add t https://example.com/l.txt
	PATH="$R/stubs:$PATH" bb list update t
	grep -q -- '--proto =https' "$R/curl.args"
	grep -q -- '--proto-redir =https' "$R/curl.args"
	grep -q -- '--max-filesize' "$R/curl.args"
	run cat "$BB_STATE_DIR/lists/t.list"
	[[ $output == *198.51.100.20* ]]
	[[ $output != *10.0.0.1* ]]
}

@test "lists: sha256 mismatch keeps the old data and fails" {
	bb __init-config --backend nft
	printf '198.51.100.30\n' >"$R/l.txt"
	bb list add t "$R/l.txt"
	bb list update t
	good=$(sha256sum "$R/l.txt" | cut -d' ' -f1)
	bb list add t "$R/l.txt" --sha256 "$(printf '0%.0s' {1..64})"
	printf '198.51.100.31\n' >"$R/l.txt"
	run bb list update t
	[ "$status" -ne 0 ]
	run cat "$BB_STATE_DIR/lists/t.list"
	[[ $output == "198.51.100.30" ]]
	bb list add t "$R/l.txt" --sha256 "$(sha256sum "$R/l.txt" | cut -d' ' -f1)"
	bb list update t
	run cat "$BB_STATE_DIR/lists/t.list"
	[[ $output == "198.51.100.31" ]]
	: "$good"
}

@test "lists: strict sanitizing of untrusted content" {
	bb __init-config --backend nft --ipv6 yes
	cat >"$R/l.txt" <<'LIST'
# comment
198.51.100.40
198.51.100.40
10.1.2.3
192.168.0.0/16
100.64.0.1
127.0.0.1
169.254.1.1
0.0.0.0/0
8.8.8.0/24 # trailing comment
$(touch PWNED)
`id`
2001:db8::/32
fc00::/7
::ffff:1.2.3.4
LIST
	bb list add t "$R/l.txt"
	bb list update t
	run sort "$BB_STATE_DIR/lists/t.list"
	[ "$output" = $'198.51.100.40\n2001:db8::/32\n8.8.8.0/24' ]
	[ ! -e PWNED ]
}

@test "lists: a supernet that contains a private range is dropped as well" {
	bb __init-config --backend nft
	printf '%s\n' 172.0.0.0/8 192.0.0.0/8 100.0.0.0/8 169.0.0.0/8 172.16.0.0/11 fe00::/9 198.51.100.40 8.8.8.0/24 >"$R/l.txt"
	bb list add t "$R/l.txt"
	bb list update t
	run sort "$BB_STATE_DIR/lists/t.list"
	[ "$output" = $'198.51.100.40\n8.8.8.0/24' ]
}

@test "lists: strip_private=no keeps private ranges" {
	bb __init-config --backend nft
	setcfg strip_private no
	printf '10.1.2.3\n198.51.100.40\n' >"$R/l.txt"
	bb list add t "$R/l.txt"
	bb list update t
	[ "$(wc -l <"$BB_STATE_DIR/lists/t.list")" -eq 2 ]
}

@test "lists: size limit rejects oversized lists" {
	bb __init-config --backend nft
	setcfg list_max_size 50
	seq -f '198.51.100.%g' 1 40 >"$R/l.txt"
	bb list add t "$R/l.txt"
	run bb list update t
	[ "$status" -ne 0 ]
	[ ! -e "$BB_STATE_DIR/lists/t.list" ]
}

@test "lists: hosts are resolved, private resolutions dropped, junk hosts ignored" {
	bb __init-config --backend nft
	printf '198.51.100.55 good.test.example\n10.9.9.9 priv.test.example\n' >"$R/hosts"
	cp /etc/hosts "$R/hosts.orig"; cat "$R/hosts.orig" >>"$R/hosts"
	mount --bind "$R/hosts" /etc/hosts
	printf 'good.test.example\npriv.test.example\nnonexistent.test.example\n-evil.example\nhttps://good.test.example:443/x\n' >"$R/l.txt"
	bb list add t "$R/l.txt"
	bb list update t
	umount /etc/hosts
	run cat "$BB_STATE_DIR/lists/t.list"
	[ "$output" = "198.51.100.55" ]
}

@test "locking: a second state-changing command waits for the lock, and fails with a message when it cannot get it" {
	bb __init-config --backend nft
	( flock 9; sleep 2 ) 9>"$BB_LOCK_FILE" &
	sleep 0.3
	BB_LOCK_WAIT=10 run bb ban 198.51.100.9           # waits, then succeeds
	[ "$status" -eq 0 ]
	( flock 9; sleep 3 ) 9>"$BB_LOCK_FILE" &
	sleep 0.3
	BB_LOCK_WAIT=1 run bb ban 198.51.100.10           # gives up
	[ "$status" -ne 0 ]
	[[ $output == *"another bb command is running"* ]]
	wait
	refute grep -q '198.51.100.10' "$BB_CONF_DIR/manual.list"
}
