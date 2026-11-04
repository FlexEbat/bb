#!/usr/bin/env bats
load helpers

TG_TOKEN='123456789:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
MX_TOKEN='syt_abcdefghijklmnop_secret'

setup() {
	setup_root
	mkdir -p "$R/sbin"
	printf '#!/bin/sh\n' >"$R/sbin/bb"; chmod +x "$R/sbin/bb"
	export BB_BIN_PATH=$R/sbin/bb BB_FORCE_IPV6=no BB_NOTIFY_SYNC=1
	printf 'ID=debian\n' >"$R/os-release"; export BB_OS_RELEASE=$R/os-release
	printf 'nameserver 198.51.100.53\n' >"$R/resolv.conf"; export BB_RESOLV_FILES=$R/resolv.conf
	cat >"$R/stubs/curl" <<STUB
#!/bin/sh
echo "\$*" >>"$R/curl.argv"
cfg=\$(cat)
printf '%s\n---\n' "\$cfg" >>"$R/curl.cfg"
[ -e "$R/curl.slow" ] && sleep 3
case "\$cfg" in *getUpdates*) cat "$R/updates.json"; exit 0 ;; esac
case "\$cfg" in *_matrix*) [ -e "$R/curl.fail.matrix" ] && exit 22 ;; esac
[ -e "$R/curl.fail" ] && exit 22
exit 0
STUB
	cat >"$R/stubs/logger" <<STUB
#!/bin/sh
echo "\$*" >>"$R/logger.log"
STUB
	cat >"$R/stubs/systemctl" <<STUB
#!/bin/sh
echo "systemctl \$*" >>"$R/sd.log"
exit 0
STUB
	chmod +x "$R/stubs/"*
	export PATH="$R/stubs:$PATH"
	bb __init-config --backend nft >/dev/null
}
teardown() { teardown_root; }

setup_tg() { printf '%s\n%s\n' "$TG_TOKEN" "-100123" | bb notify setup telegram; }
setup_mx() { printf '%s\n%s\n%s\n' "https://matrix.example.org" "$MX_TOKEN" '!abc:example.org' | bb notify setup matrix; }
sends() { [ -e "$R/curl.cfg" ] && grep -c 'sendMessage\|send/m.room.message' "$R/curl.cfg" || echo 0; }
last_cfg() { awk -v RS='---\n' 'END { print }' "$R/curl.cfg"; }
queue_len() { [ -s "$BB_STATE_DIR/notify.queue" ] && wc -l <"$BB_STATE_DIR/notify.queue" || echo 0; }
events() { bb notify events "$1" >/dev/null; }

@test "telegram setup: verified with a test message, secrets only in notify.conf (0600)" {
	run setup_tg
	[ "$status" -eq 0 ]
	[[ $output == *"saved"* ]]
	[ "$(stat -c %a "$BB_CONF_DIR/notify.conf")" = 600 ]
	grep -q "$TG_TOKEN" "$BB_CONF_DIR/notify.conf"
	grep -q "^notify_enabled='yes'" "$BB_CONF_DIR/bb.conf"
	refute grep -q "$TG_TOKEN" "$BB_CONF_DIR/bb.conf"
	cfg=$(last_cfg)
	[[ $cfg == *'url = "https://api.telegram.org/bot'*'/sendMessage"'* ]]
	[[ $cfg == *'chat_id=-100123'* ]]
	[[ $cfg == *'text=['*'] test: notifications are working (mode: monitor, backend: nft)'* ]]
	[[ $cfg == *'proto = "=https"'* && $cfg == *'max-time = 10'* ]]
}

@test "secrets never appear in the process list, output, status or journal" {
	setup_tg >"$R/out" 2>&1
	setup_mx >>"$R/out" 2>&1
	bb notify test >>"$R/out" 2>&1
	bb notify status >>"$R/out" 2>&1
	bb status >>"$R/out" 2>&1 || true
	bb ban 198.51.100.7 >>"$R/out" 2>&1
	events manual_change,mode_changed
	bb ban 198.51.100.8 >>"$R/out" 2>&1
	refute grep -q -e "$TG_TOKEN" -e "$MX_TOKEN" -e 'abc:example.org' "$R/curl.argv"      # curl's argv
	refute grep -q -e "$TG_TOKEN" -e "$MX_TOKEN" "$R/out"                                  # any bb output
	refute grep -q -e "$TG_TOKEN" -e "$MX_TOKEN" "$R/logger.log"                           # journald
	[ "$(sort -u "$R/curl.argv")" = "-K -" ]                                               # argv is only "-K -"
	grep -q "$MX_TOKEN" "$R/curl.cfg"                                                      # ...they travel on stdin
}

@test "setup rejects bad input before touching the network and saves nothing on a failed test" {
	run bash -c "printf 'not-a-token\n-100123\n' | '$BB' notify setup telegram"
	[ "$status" -ne 0 ]
	[ ! -e "$R/curl.argv" ]
	touch "$R/curl.fail"
	run setup_tg
	[ "$status" -ne 0 ]
	[[ $output == *"nothing was saved"* ]]
	[ ! -e "$BB_CONF_DIR/notify.conf" ]
	grep -q "^notify_enabled='no'" "$BB_CONF_DIR/bb.conf"
	refute grep -q "$TG_TOKEN" "$R/out" 2>/dev/null
	[[ $output != *"$TG_TOKEN"* ]]
}

@test "telegram: chat id is detected with getUpdates (jq)" {
	printf '{"ok":true,"result":[{"update_id":1,"message":{"chat":{"id":424242,"type":"private"}}}]}' >"$R/updates.json"
	run bash -c "printf '%s\n\n\n' '$TG_TOKEN' | '$BB' notify setup telegram"
	[ "$status" -eq 0 ]
	grep -q "^notify_telegram_chat='424242'" "$BB_CONF_DIR/notify.conf"
}

@test "matrix: PUT with bearer header, room encoded, JSON built by jq" {
	run setup_mx
	[ "$status" -eq 0 ]
	cfg=$(last_cfg)
	[[ $cfg == *'url = "https://matrix.example.org/_matrix/client/v3/rooms/%21abc%3Aexample.org/send/m.room.message/'* ]]
	[[ $cfg == *'request = "PUT"'* ]]
	[[ $cfg == *"header = \"Authorization: Bearer $MX_TOKEN\""* ]]
	data=$(printf '%s\n' "$cfg" | sed -n 's/^data = "\(.*\)"$/\1/p' | sed 's/\\"/"/g')
	[ "$(jq -r .msgtype <<<"$data")" = m.text ]
	[[ $(jq -r .body <<<"$data") == "["*"] test: notifications are working"* ]]
}

@test "untrusted event data cannot inject into messages or curl config" {
	setup_tg >/dev/null
	bb __notify-event list_update_failed 'name=evil"
url = "https://attacker.example/x'
	bb __notify-event list_update_failed 'name=a"b\c;d'
	[ "$(grep -c '^url = ' "$R/curl.cfg")" -eq 3 ]        # test message + 2 events, no injected url
	refute grep -q 'attacker' "$R/curl.cfg"
	[ "$(grep -c '^data-urlencode = "text=' "$R/curl.cfg")" -eq 3 ]
	grep -q 'list_update_failed: download of list a?b?c?d failed' "$R/curl.cfg"
}

@test "events: only the enabled ones are sent; manual changes never carry the address" {
	setup_tg >/dev/null; n=$(sends)
	bb ban 198.51.100.7
	[ "$(sends)" -eq "$n" ]                              # manual_change is not on by default
	events mode_changed,manual_change
	bb ban 198.51.100.8
	[ "$(sends)" -eq $((n + 1)) ]
	cfg=$(last_cfg)
	[[ $cfg == *'manual_change: manual change: ban'* ]]
	[[ $cfg != *198.51.100* ]]
	run bb notify events bogus
	[ "$status" -ne 0 ]
}

@test "mode change notification, in English and in Russian (event id stays English)" {
	setup_tg >/dev/null
	bb apply >/dev/null
	bb mode block >/dev/null
	cfg=$(last_cfg)
	[[ $cfg == *'mode_changed: mode is now block (mode: block, backend: nft)'* ]]
	setcfg notify_lang ru
	bb mode monitor >/dev/null
	cfg=$(last_cfg)
	[[ $cfg == *'mode_changed: теперь режим monitor (режим: monitor, бэкенд: nft)'* ]]
}

@test "flood protection: identical events are suppressed for notify_dedup" {
	setup_tg >/dev/null; n=$(sends)
	bb __notify-event service_failed unit=bb-guard.service
	bb __notify-event service_failed unit=bb-guard.service
	[ "$(sends)" -eq $((n + 1)) ]
	setcfg notify_dedup 1s
	sleep 2
	bb __notify-event service_failed unit=bb-guard.service
	[ "$(sends)" -eq $((n + 2)) ]
}

@test "flood protection: global hourly limit, one summary message afterwards" {
	setup_tg >/dev/null
	setcfg notify_rate_limit 3
	rm -f "$BB_STATE_DIR/notify.rate"; n=$(sends)
	for i in 1 2 3 4 5; do bb __notify-event service_failed unit=u$i.service; done
	[ "$(sends)" -eq $((n + 3)) ]
	[ "$(cat "$BB_STATE_DIR/notify.suppressed")" -eq 2 ]
	run bb notify status; [[ $output == *"suppressed: 2"* ]]
	awk '{ print $1 - 7200 }' "$BB_STATE_DIR/notify.rate" >"$R/rate.old" && cp "$R/rate.old" "$BB_STATE_DIR/notify.rate"
	bb __notify-flush
	[ "$(sends)" -eq $((n + 4)) ]
	grep -q 'rate_limit: suppressed notifications: 2' "$R/curl.cfg"
	[ ! -e "$BB_STATE_DIR/notify.suppressed" ]
	bb __notify-flush
	[ "$(sends)" -eq $((n + 4)) ]                        # the summary is sent once
}

@test "queue: undelivered messages are kept and retried; per-channel progress is remembered" {
	setup_tg >/dev/null; setup_mx >/dev/null
	touch "$R/curl.fail"; n=$(sends)
	bb __notify-event service_failed unit=a.service
	[ "$(queue_len)" -eq 1 ]
	run bb notify status; [[ $output == *"Queue: 1"* ]]
	touch "$R/curl.fail.matrix"; rm "$R/curl.fail"        # telegram recovers, matrix stays down
	bb __notify-flush
	[ "$(queue_len)" -eq 1 ]
	[ "$(cut -f3 "$BB_STATE_DIR/notify.queue")" = matrix ]
	rm "$R/curl.fail.matrix"
	bb __notify-flush
	[ "$(queue_len)" -eq 0 ]
}

@test "queue: expired messages are discarded, not sent" {
	setup_tg >/dev/null
	setcfg notify_queue_ttl 1s
	touch "$R/curl.fail"
	bb __notify-event service_failed unit=old.service
	[ "$(queue_len)" -eq 1 ]
	sleep 2; rm "$R/curl.fail"; n=$(sends)
	bb __notify-flush
	[ "$(queue_len)" -eq 0 ]
	[ "$(sends)" -eq "$n" ]
}

@test "queue: bounded, the oldest messages are dropped first" {
	setup_tg >/dev/null
	setcfg notify_queue_max 3; setcfg notify_rate_limit 100
	touch "$R/curl.fail"
	for i in 1 2 3 4 5; do bb __notify-event service_failed unit=m$i.service; done
	[ "$(queue_len)" -eq 3 ]
	first=$(head -1 "$BB_STATE_DIR/notify.queue" | cut -f4 | base64 -d)
	[[ $first == *m3.service* ]]
}

@test "delivery is in the background: a dead network never delays or fails a firewall command" {
	setup_tg >/dev/null; events manual_change
	touch "$R/curl.slow" "$R/curl.fail"
	unset BB_NOTIFY_SYNC
	start=$(date +%s)
	bb ban 198.51.100.7
	bb ban 198.51.100.8                                  # would wait 30 s on the lock if the child kept it
	[ $(($(date +%s) - start)) -lt 3 ]
	for i in $(seq 1 30); do [ "$(queue_len)" -ge 1 ] && break; sleep 0.3; done
	[ "$(queue_len)" -ge 1 ]                              # failed delivery ended up in the queue
	grep -q '198.51.100.7' "$BB_CONF_DIR/manual.list"     # and the operation itself succeeded
}

@test "notification endpoints are allowlisted so blocklists cannot cut the channel off" {
	cp /etc/hosts "$R/hosts"; printf '198.51.100.77 api.telegram.org\n' >>"$R/hosts"
	mount --bind "$R/hosts" /etc/hosts
	bb apply >/dev/null
	setup_tg >/dev/null
	grep -qx '198.51.100.77' "$BB_STATE_DIR/notify.allow"
	run nft list set inet bb allow4; [[ $output == *198.51.100.77* ]]
	bb apply >/dev/null                                   # survives a rebuild without DNS
	run nft list set inet bb allow4; [[ $output == *198.51.100.77* ]]
	bb notify disable >/dev/null
	[ ! -e "$BB_STATE_DIR/notify.allow" ]
	run nft list set inet bb allow4; [[ $output != *198.51.100.77* ]]
	umount /etc/hosts
}

@test "guard retries the queue and reports restored rules" {
	setup_tg >/dev/null; bb apply >/dev/null
	touch "$R/curl.fail"
	bb __notify-event service_failed unit=x.service
	[ "$(queue_len)" -eq 1 ]
	rm "$R/curl.fail"
	nft flush ruleset
	bb guard >/dev/null
	[ "$(queue_len)" -eq 0 ]
	grep -q 'guard_restored: the rules were missing or displaced' "$R/curl.cfg"
}

@test "list problems are reported with the list name and a translated reason" {
	setup_tg >/dev/null
	printf '198.51.100.1\n' >"$R/l.txt"
	bb list add t "$R/l.txt"; bb list update t >/dev/null
	: >"$R/l.txt"
	run bb list update t; [ "$status" -ne 0 ]
	grep -q 'list_rejected: list t rejected: no valid entries' "$R/curl.cfg"
	rm "$R/l.txt"
	run bb list update t; [ "$status" -ne 0 ]
	grep -q 'list_update_failed: download of list t failed' "$R/curl.cfg"
}

@test "enable/disable/status and the Russian CLI" {
	run bb notify enable; [ "$status" -ne 0 ]             # nothing configured yet
	setup_tg >/dev/null
	bb notify disable >/dev/null
	run bb notify status; [[ $output == *"Notifications: off"* ]]
	n=$(sends); bb __notify-event service_failed unit=q.service
	[ "$(sends)" -eq "$n" ]
	bb notify enable >/dev/null
	run bb --lang ru notify status
	[[ $output == *"Уведомления: включены"* && $output == *"Канал telegram: настроен"* && $output == *"Канал matrix: не настроен"* ]]
}

@test "proxy is passed in the curl config and validated" {
	setup_tg >/dev/null
	setcfg notify_proxy 'socks5://127.0.0.1:1080'
	bb __notify-event service_failed unit=p.service
	[[ $(last_cfg) == *'proxy = "socks5://127.0.0.1:1080"'* ]]
	setcfg notify_proxy 'ftp://nope'
	run bb mode
	[[ $output == *"notify_proxy"* ]]                     # invalid value is reported, default used
}

@test "daily digest: modes, sets, packets since last time, list sizes; no addresses" {
	setup_tg >/dev/null; bb apply >/dev/null
	printf '198.51.100.9\n' >"$R/l.txt"; bb list add t "$R/l.txt"; bb list update t >/dev/null
	cat >"$R/stubs/journalctl" <<STUB
#!/bin/sh
printf 'guard_restored backend=nft\nlist_rejected name=t reason=empty\nguard_restored backend=nft\n'
STUB
	chmod +x "$R/stubs/journalctl"
	events mode_changed,digest
	grep -q 'enable --now bb-digest.timer' "$R/sd.log"
	bb __digest
	cfg=$(last_cfg)
	[[ $cfg == *'digest:'* && $cfg == *'Mode: monitor, backend: nft'* ]]
	[[ $cfg == *'Sets: '* && $cfg == *'Packets since the previous digest: '* ]]
	[[ $cfg == *'Lists (entries): t=1'* ]]
	[[ $cfg == *'Events in 24 h: guard_restored=2 list_update_failed=0 list_rejected=1'* ]]
	[[ ! $cfg =~ [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]
	[ -s "$BB_STATE_DIR/digest.counters" ]
	events mode_changed
	grep -q 'disable --now bb-digest.timer' "$R/sd.log"
}

@test "units: failure hook and digest are wired, and systemd-analyze accepts them" {
	run bb __unit bb-notify-failure@.service
	[[ $output == *"__notify-event service_failed unit=%i"* ]]
	for u in bb-firewall bb-update bb-guard bb-digest; do
		run bb __unit $u.service
		[[ $output == *"OnFailure=bb-notify-failure@%n.service"* ]]
	done
	run bb __unit bb-sets.service; [[ $output != *OnFailure* ]]
	command -v systemd-analyze >/dev/null || skip "systemd-analyze not available"
	mkdir -p "$R/u"
	for u in bb-firewall.service bb-update.service bb-update.timer bb-guard.service bb-guard.timer bb-digest.service bb-digest.timer 'bb-notify-failure@.service'; do bb __unit "$u" >"$R/u/$u"; done
	run systemd-analyze verify "$R"/u/*.service "$R"/u/*.timer
	echo "$output"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "service_failed message names the unit" {
	setup_tg >/dev/null
	bb __notify-event service_failed unit=bb-guard.service
	grep -q 'service_failed: unit bb-guard.service failed' "$R/curl.cfg"
}

@test "install and uninstall are announced (uninstall synchronously, before removal)" {
	mkdir -p "$R/units"; export BB_UNIT_DIR=$R/units
	setup_tg >/dev/null
	events install,uninstall
	bb install --backend nft --yes --iface lo >/dev/null
	grep -q 'install: bb installed, backend nft' "$R/curl.cfg"
	unset BB_NOTIFY_SYNC
	bb uninstall --yes >/dev/null
	grep -q 'uninstall: bb removed' "$R/curl.cfg"
	[ ! -e "$BB_UNIT_DIR/bb-guard.timer" ]
}

# every line of a curl config block must be a known option: a stray line means injection
cfg_wellformed() {
	! printf '%s\n' "$1" | grep -vE '^(url|data-urlencode|data|header|request|proxy) = ".*"$|^(silent|fail)$|^(max-time|connect-timeout) = [0-9]+$|^proto = "=https"$|^output = "/dev/null"$|^$' | grep -q .
}

@test "curl config quoting: quotes, backslashes and newlines cannot break out of a value" {
	run bash -c "source <(sed -n '/^curl_q() {/,/^}/p' '$BB'); curl_q \$'a\"b\\\\c\nd\te'"
	[ "$status" -eq 0 ]
	[ "$output" = 'a\"b\\c\nd\te' ]
}

@test "the multi-line digest is one well-formed curl config value" {
	setup_tg >/dev/null; bb apply >/dev/null
	events digest
	bb __digest
	cfg=$(last_cfg)
	[ "$(printf '%s\n' "$cfg" | grep -c '^data-urlencode = "text=')" -eq 1 ]
	[[ $cfg == *'\n'* ]]                                  # the newlines were escaped, not emitted
	cfg_wellformed "$cfg" || { echo "stray line in curl config:"; echo "$cfg"; return 1; }
}

@test "matrix messages are valid JSON even for multi-line bodies" {
	setup_mx >/dev/null; bb apply >/dev/null
	events digest
	bb __digest
	data=$(last_cfg | sed -n 's/^data = "\(.*\)"$/\1/p' | sed 's/\\"/"/g; s/\\\\/\\/g')
	[ "$(jq -r .msgtype <<<"$data")" = m.text ]
	[[ $(jq -r .body <<<"$data") == *$'\n'* ]]
}
