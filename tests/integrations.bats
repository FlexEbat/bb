#!/usr/bin/env bats
load helpers

setup() {
	setup_root
	mkdir -p "$R/sbin" "$R/k3s" "$R/manifests"
	printf '#!/bin/sh\n' >"$R/sbin/bb"; chmod +x "$R/sbin/bb"
	export BB_BIN_PATH=$R/sbin/bb BB_FORCE_IPV6=yes
	export BB_K3S_DIR=$R/k3s BB_KUBE_MANIFEST_DIR=$R/manifests
	export BB_UFW_CONF=$R/ufw.conf BB_FIREWALLD_CONF=$R/firewalld.conf BB_NFTABLES_CONF=$R/nftables.conf
	printf 'ID=debian\n' >"$R/os-release"; export BB_OS_RELEASE=$R/os-release
	export BB_SAVED_FILES=""
	: >"$R/resolv.conf"; export BB_RESOLV_FILES=$R/resolv.conf     # no DNS servers to auto-allow
	cat >"$R/stubs/systemctl" <<STUB
#!/bin/sh
echo "systemctl \$*" >>"$R/sd.log"
exit 0
STUB
	chmod +x "$R/stubs/"*
	export PATH="$R/stubs:$PATH"
	rm -rf "$R/k3s" "$R/manifests"       # absent unless a test creates them
}
teardown() {
	for i in docker0 br-abcdef br-new dkr0p dkr1p dkr2p; do ip link del "$i" 2>/dev/null; done
	ip addr del 192.0.2.50/32 dev lo 2>/dev/null
	teardown_root
}

init() { bb __init-config --backend "$1" --ipv6 yes >/dev/null; bb apply >/dev/null; }
mk_if() { ip link add "$1" type veth peer name "$3"; ip addr add "$2" dev "$1"; ip link set "$1" up; ip link set "$3" up; }
in_set() { # set net|addr: membership of the (base) address, robust against nft merging adjacent networks
	local a=${2%%/*}
	if grep -q "^backend='nft'" "$BB_CONF_DIR/bb.conf"; then nft get element inet bb "$1" "{ $a }" >/dev/null 2>&1
	else ipset test "bb_$1" "$a" >/dev/null 2>&1; fi
}
refute_in_set() { if in_set "$@"; then echo "unexpected $2 in $1"; return 1; fi; }
stub_docker() {
	cat >"$R/stubs/docker" <<STUB
#!/bin/sh
echo "docker \$*" >>"$R/docker.log"
case "\$2" in
	ls) echo "abc123"; echo "def456" ;;
	inspect) echo "172.30.0.0/16 fd00:30::/64 " ;;
esac
STUB
	chmod +x "$R/stubs/docker"
}

t_docker_ifaces() {
	init "$1"
	mk_if docker0 172.17.0.1/16 dkr0p
	mk_if br-abcdef 172.20.0.1/16 dkr1p
	bb integrate auto >/dev/null
	in_set internal4 172.17.0.0/16
	in_set internal4 172.20.0.0/16
	refute_in_set internal4 198.51.100.0/24
	refute_in_set allow4 172.17.0.0/16                 # not in the either-end allowlist
}

# Does a datagram from the peer ("a pod") reach a listener bound to the banned address?
# (A ping would hide the difference: the reply from a banned address is dropped anyway.)
pod_reaches_blocked() {
	rm -f "$R/b.out"
	nc -u -l 192.0.2.50 9999 >"$R/b.out" &
	local pid=$!
	sleep 0.3
	ip netns exec bbpeer sh -c 'printf hi | nc -u -w1 192.0.2.50 9999' 2>/dev/null
	sleep 0.4
	kill "$pid" 2>/dev/null; pkill -f 'nc -u -l' 2>/dev/null; wait "$pid" 2>/dev/null || true
	[[ -s $R/b.out ]]
}

t_traffic_semantics() {
	init "$1"; topo_up
	ip addr add 192.0.2.50/32 dev lo
	ip -n bbpeer route add 192.0.2.50/32 via 198.51.100.1
	setcfg k8s_pod_cidr 198.51.100.0/24; bb integrate k8s >/dev/null     # the peer is "a pod"
	bb ban 192.0.2.50 >/dev/null; bb ban 198.51.100.1 >/dev/null; bb ban 198.51.100.2 >/dev/null
	pod_reaches_blocked || { echo "monitor mode must let the datagram through"; return 1; }
	bb mode block >/dev/null
	ip netns exec bbpeer ping -c1 -W1 198.51.100.1 >/dev/null      # pod -> pod/host-in-pod-net: passes even though banned
	ping -c1 -W1 198.51.100.2 >/dev/null                            # and the other way round
	if pod_reaches_blocked; then echo "pod -> blocked address was NOT dropped"; return 1; fi
	run bb status; [[ $output =~ manual[[:space:]]+packets[[:space:]]+[1-9] ]]
	bb integrate none >/dev/null                                    # without the integration the pod net is not special
	if ping -c1 -W1 198.51.100.2 >/dev/null 2>&1; then echo "banned peer reachable without the integration"; return 1; fi
}

t_nodes_allow() {
	init "$1"; topo_up
	ip addr add 192.0.2.50/32 dev lo
	ip -n bbpeer route add 192.0.2.50/32 via 198.51.100.1
	cat >"$R/stubs/kubectl" <<STUB
#!/bin/sh
printf 'InternalIP=198.51.100.2\nExternalIP=203.0.113.9\nHostname=node1\n'
STUB
	chmod +x "$R/stubs/kubectl"
	mkdir -p "$R/k3s"; : >"$R/k3s/config.yaml"
	bb ban 198.51.100.2 >/dev/null; bb mode block >/dev/null
	if ping -c1 -W1 198.51.100.2 >/dev/null 2>&1; then echo "banned node reachable before the integration"; return 1; fi
	bb integrate k8s >/dev/null
	in_set allow4 198.51.100.2
	in_set allow4 203.0.113.9
	refute_in_set internal4 198.51.100.2                # node addresses are plain allowlist entries
	ping -c1 -W1 198.51.100.2 >/dev/null                # the allowlist wins over the manual ban
}

t_guard_refresh() {
	init "$1"
	mk_if docker0 172.17.0.1/16 dkr0p
	bb integrate auto >/dev/null
	refute_in_set internal4 172.22.0.0/16
	mk_if br-new 172.22.0.1/16 dkr1p                   # a compose project appears
	bb guard >/dev/null
	in_set internal4 172.22.0.0/16
	in_set internal4 172.17.0.0/16
}

t_offline_boot() { # after a reboot the networks come from the cache, no docker/kubectl needed
	init "$1"; stub_docker
	bb integrate docker >/dev/null
	in_set internal4 172.30.0.0/16
	bb __remove
	rm -f "$R/docker.log" "$R/stubs/docker"
	bb apply >/dev/null
	in_set internal4 172.30.0.0/16
	[ ! -e "$R/docker.log" ]
}

@test "nft: docker0 and br-* networks go to the internal set" { t_docker_ifaces nft; }
@test "iptables: docker0 and br-* networks go to the internal set" { t_docker_ifaces iptables; }
@test "nft: containers/pods talk to each other, but not to blocked addresses" { t_traffic_semantics nft; }
@test "iptables: containers/pods talk to each other, but not to blocked addresses" { t_traffic_semantics iptables; }
@test "nft: node addresses (kubectl) join the allowlist and beat a ban" { t_nodes_allow nft; }
@test "iptables: node addresses (kubectl) join the allowlist and beat a ban" { t_nodes_allow iptables; }
@test "nft: guard picks up new Docker networks" { t_guard_refresh nft; }
@test "iptables: guard picks up new Docker networks" { t_guard_refresh iptables; }
@test "nft: after a reboot the internal networks load from the cache" { t_offline_boot nft; }
@test "iptables: after a reboot the internal networks load from the cache" { t_offline_boot iptables; }

@test "docker network inspect adds subnets, IPv6 included" {
	init nft; stub_docker
	bb integrate docker >/dev/null
	in_set internal4 172.30.0.0/16
	in_set internal6 fd00:30::/64
	grep -q 'docker network ls -q' "$R/docker.log"
}

@test "k3s config: inline, quoted, dual-stack, list form and config.d are all understood" {
	init nft
	mkdir -p "$R/k3s/config.yaml.d"
	cat >"$R/k3s/config.yaml" <<'YAML'
# comment
write-kubeconfig-mode: "0644"
cluster-cidr: "10.52.0.0/16,fd00:52::/56"   # dual-stack
service-cidr:
  - 10.53.0.0/16
  - fd00:53::/112
YAML
	printf 'cluster-cidr: 10.60.0.0/16\n' >"$R/k3s/config.yaml.d/10-extra.yaml"
	bb integrate k8s >/dev/null
	for n in 10.52.0.0/16 10.60.0.0/16 10.53.0.0/16; do in_set internal4 $n; done
	for n in fd00:52::/56 fd00:53::/112; do in_set internal6 $n; done
	refute_in_set internal4 10.42.0.0/16                # explicit settings replace the defaults
}

@test "k3s defaults, kubeadm manifests and manual settings" {
	init nft
	mkdir -p "$R/k3s"
	bb integrate k8s >/dev/null
	in_set internal4 10.42.0.0/16; in_set internal4 10.43.0.0/16          # k3s defaults
	rm -rf "$R/k3s"; mkdir -p "$R/manifests"
	cat >"$R/manifests/kube-controller-manager.yaml" <<'YAML'
spec:
  containers:
  - command:
    - kube-controller-manager
    - --cluster-cidr=10.244.0.0/16
    - --service-cluster-ip-range=10.96.0.0/12
YAML
	bb integrate k8s >/dev/null; bb guard >/dev/null
	in_set internal4 10.244.0.0/16; in_set internal4 10.96.0.0/12
	refute_in_set internal4 10.42.0.0/16
	rm -rf "$R/manifests"
	setcfg k8s_pod_cidr 192.168.77.0/24,fd77::/64; setcfg k8s_service_cidr 192.168.78.0/24
	bb guard >/dev/null
	in_set internal4 192.168.77.0/24; in_set internal4 192.168.78.0/24; in_set internal6 fd77::/64
	run bb mode; setcfg k8s_pod_cidr 'not-a-cidr'; run bb mode; [[ $output == *k8s_pod_cidr* ]]
}

@test "bb integrate: selection, none, auto, errors and status" {
	init nft; mkdir -p "$R/k3s"; mk_if docker0 172.17.0.1/16 dkr0p
	run bb integrate bogus; [ "$status" -ne 0 ]
	run bb integrate status
	[[ $output == *"docker"*"detected"* && $output == *"k8s"*"detected"* && $output == *"ufw"*"not found"* ]]
	bb integrate docker >/dev/null
	grep -q "^integrations='docker'" "$BB_CONF_DIR/bb.conf"
	in_set internal4 172.17.0.0/16; refute_in_set internal4 10.42.0.0/16
	bb integrate k8s >/dev/null
	grep -q "^integrations='docker,k8s'" "$BB_CONF_DIR/bb.conf"
	in_set internal4 10.42.0.0/16
	bb integrate none >/dev/null
	refute_in_set internal4 172.17.0.0/16
	[ ! -s "$BB_STATE_DIR/integrations.internal" ]
	bb integrate auto >/dev/null
	in_set internal4 172.17.0.0/16
	run bb --lang ru integrate status; [[ $output == *"обнаружен"* && $output == *"не найден"* ]]
}

@test "ufw and firewalld are reported, never modified" {
	init nft
	printf 'ENABLED=yes\n' >"$R/ufw.conf"
	printf 'FirewallBackend=nftables\n' >"$R/firewalld.conf"
	printf '#!/bin/sh\n[ "$1" = --state ] && echo running\n' >"$R/stubs/firewall-cmd"; chmod +x "$R/stubs/firewall-cmd"
	run bb integrate status
	[[ $output == *"ufw"*"active"* && $output == *"firewalld"*"active"*"nftables"* ]]
	bb integrate ufw >/dev/null; bb integrate firewalld >/dev/null
	grep -q "^integrations='ufw,firewalld'" "$BB_CONF_DIR/bb.conf"
	[ ! -s "$BB_STATE_DIR/integrations.internal" ]       # they add no networks
	run nft list tables; [[ $output == *"inet bb"* ]]
}

@test "integration changes are announced once" {
	export BB_NOTIFY_SYNC=1
	cat >"$R/stubs/curl" <<STUB
#!/bin/sh
cat >>"$R/curl.cfg"; echo --- >>"$R/curl.cfg"
STUB
	chmod +x "$R/stubs/curl"
	init nft
	printf 'notify_telegram_token='"'"'123456789:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'"'"'\nnotify_telegram_chat='"'"'-100123'"'"'\n' >"$BB_CONF_DIR/notify.conf"
	chmod 600 "$BB_CONF_DIR/notify.conf"
	setcfg notify_enabled yes; setcfg notify_events integration_changed
	mk_if docker0 172.17.0.1/16 dkr0p
	bb integrate auto >/dev/null
	[ "$(grep -c 'integration_changed: the integration allowlist was changed' "$R/curl.cfg")" -eq 1 ]
	bb guard >/dev/null; bb guard >/dev/null            # nothing changed: nothing sent
	[ "$(grep -c 'integration_changed' "$R/curl.cfg")" -eq 1 ]
	setcfg notify_dedup 1s; sleep 2                      # identical texts are deduplicated for notify_dedup
	mk_if br-new 172.22.0.1/16 dkr1p
	bb guard >/dev/null
	[ "$(grep -c 'integration_changed' "$R/curl.cfg")" -eq 2 ]
}

@test "install detects integrations and says so; uninstall leaves no bb objects" {
	mkdir -p "$R/units"; export BB_UNIT_DIR=$R/units
	mk_if docker0 172.17.0.1/16 dkr0p
	run bb install --no-dpi --backend nft --yes --iface lo
	[ "$status" -eq 0 ]
	[[ $output == *"Integrations: 1 internal networks"* ]]
	nft list set inet bb internal4 | grep -qF 172.17.0.0/16
	bb uninstall --yes >/dev/null
	run nft list tables; [[ $output != *"inet bb"* ]]
	[ ! -e "$BB_STATE_DIR" ]
}

# ---- bb doctor -------------------------------------------------------------------------------
doc_install() {
	mkdir -p "$R/units"; export BB_UNIT_DIR=$R/units
	bb install --no-dpi --backend "${1:-nft}" --yes --iface lo >/dev/null
	bb allow 192.0.2.1 >/dev/null
}

@test "doctor: healthy system exits 0 and reports each area" {
	doc_install
	run bb doctor
	echo "$output"
	[ "$status" -eq 0 ]
	[[ $output == *"[  ok] backend nft: all required tools are present"* ]]
	[[ $output == *"[  ok] kernel support for nf_tables is available"* ]]
	[[ $output == *"[  ok] the bb chain/table is present and the jump is in first position"* ]]
	[[ $output == *"[  ok] unit bb-firewall.service is enabled"* ]]
	[[ $output == *"[  ok] the allowlist has "* ]]
	[[ $output == *"[  ok] language catalogs are in place (selected: en)"* ]]
	[[ $output == *"Problems: 0"* ]]
}

@test "doctor (iptables): variant, sets service, jump position" {
	doc_install iptables
	run bb doctor
	[ "$status" -eq 0 ]
	[[ $output == *"iptables variant: "* && $output == *"unit bb-sets.service is enabled"* ]]
	iptables -t raw -I PREROUTING 1 -s 1.2.3.4 -j ACCEPT
	run bb doctor
	[ "$status" -eq 1 ]
	[[ $output == *"[FAIL] the bb rules are missing or displaced"* ]]
	bb guard >/dev/null
	run bb doctor; [ "$status" -eq 0 ]
}

@test "doctor: wiped rules are a FAIL, an empty allowlist and queued messages are warnings" {
	mkdir -p "$R/units"; export BB_UNIT_DIR=$R/units
	bb install --no-dpi --backend nft --yes --iface lo >/dev/null
	run bb doctor
	[ "$status" -eq 0 ]
	[[ $output == *"[warn] the allowlist is empty"* ]]
	nft flush ruleset
	run bb doctor
	[ "$status" -eq 1 ]
	[[ $output == *"[FAIL] the bb rules are missing or displaced"* && $output == *"Problems: 1"* ]]
}

@test "doctor: nftables.service with 'flush ruleset' is called out" {
	doc_install
	printf '#!/usr/sbin/nft -f\nflush ruleset\ntable inet filter {}\n' >"$R/nftables.conf"
	run bb doctor
	[ "$status" -eq 0 ]
	[[ $output == *"[warn] nftables.service is enabled and $R/nftables.conf starts with 'flush ruleset'"* ]]
	printf 'table inet filter {}\n' >"$R/nftables.conf"
	run bb doctor
	[[ $output == *"[  ok] nftables.service does not flush the ruleset"* ]]
}

@test "doctor: saved rule files that mention bb objects" {
	doc_install iptables
	printf '*raw\n:BB_FILTER - [0:0]\nCOMMIT\n' >"$R/rules.v4"
	BB_SAVED_FILES=$R/rules.v4 run bb doctor
	[[ $output == *"[warn] saved rules file $R/rules.v4 mentions bb objects"* ]]
}

@test "doctor: notify.conf permissions, queue size and no secrets in the output" {
	doc_install
	printf "notify_telegram_token='123456789:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'\nnotify_telegram_chat='-1001'\n" >"$BB_CONF_DIR/notify.conf"
	chmod 644 "$BB_CONF_DIR/notify.conf"
	run bb doctor
	[ "$status" -eq 1 ]
	[[ $output == *"[FAIL] notify.conf must be owned by root with mode 0600 (found 644)"* ]]
	[[ $output != *AAAAAAAA* ]]
	chmod 600 "$BB_CONF_DIR/notify.conf"
	printf '1\t%s\ttelegram\tYQ==\n' "$(date +%s)" >"$BB_STATE_DIR/notify.queue"
	run bb doctor
	[ "$status" -eq 0 ]
	[[ $output == *"[  ok] notify.conf is owned by root with mode 0600"* && $output == *"[warn] the notification queue holds 1 undelivered messages"* ]]
}

@test "doctor: missing language catalog and an unsafe bb.conf mode" {
	doc_install
	mkdir -p "$R/share2/lang"; cp "$REPO/lang/en.sh" "$R/share2/lang/"; ln -s "$REPO/src/net.awk" "$R/share2/net.awk"
	BB_SHARE_DIR=$R/share2 run bb doctor
	[ "$status" -eq 1 ]
	[[ $output == *"[FAIL] language catalog ru.sh is missing"* ]]
	chmod 644 "$BB_CONF_DIR/bb.conf"
	run bb doctor
	[[ $output == *"[warn] bb.conf should have mode 0600 (found 644)"* ]]
}

@test "doctor: other firewall tools and integrations are listed, ufw advice, SELinux/AVC" {
	mkdir -p "$R/units"; export BB_UNIT_DIR=$R/units
	bb install --no-dpi --backend nft --yes --iface lo >/dev/null     # allowlist stays empty on purpose
	iptables -N f2b-sshd; iptables -N ts-input
	mk_if docker0 172.17.0.1/16 dkr0p
	printf 'ENABLED=yes\n' >"$R/ufw.conf"
	printf '#!/bin/sh\necho Enforcing\n' >"$R/stubs/getenforce"
	printf '#!/bin/sh\nprintf "type=AVC msg=a\\ntype=AVC msg=b\\n"\n' >"$R/stubs/ausearch"
	chmod +x "$R/stubs/"*
	bb integrate auto >/dev/null
	run bb doctor
	echo "$output"
	[[ $output == *"other firewall tools detected: fail2ban tailscale"* ]]
	[[ $output == *"Docker: 1 container networks are known"* ]]
	[[ $output == *"[warn] ufw is active: 'ufw allow' does not exempt anyone from bb"* ]]
	[[ $output == *"SELinux: Enforcing"* && $output == *"SELinux denied bb 2 times"* ]]
}

@test "doctor: k8s without known networks is a warning" {
	doc_install
	mkdir -p "$R/manifests"          # kubeadm layout present but without the flags
	run bb doctor
	[[ $output == *"[warn] k3s/k8s detected but the pod/service networks are unknown"* ]]
}

@test "doctor: Russian output, same exit codes" {
	doc_install
	run bb --lang ru doctor
	[ "$status" -eq 0 ]
	[[ $output == *"бэкенд nft: все необходимые утилиты на месте"* && $output == *"Проблем: 0"* ]]
	nft flush ruleset
	run bb --lang ru doctor
	[ "$status" -eq 1 ]
	[[ $output == *"[СБОЙ]"* ]]
}
