#!/usr/bin/env bats
load helpers

HELP=$BATS_TEST_DIRNAME/fixtures/ndpid-help.txt
FIX=$BATS_TEST_DIRNAME/fixtures/ndpid-1.7.raw

setup() {
	setup_root
	mkdir -p "$R/sbin" "$R/bin" "$R/units"
	printf '#!/bin/sh\n' >"$R/sbin/bb"; chmod +x "$R/sbin/bb"
	export BB_BIN_PATH=$R/sbin/bb BB_NDPID_BIN=$R/bin/bb-ndpid BB_RUN_DIR=$R/run BB_UNIT_DIR=$R/units BB_FORCE_IPV6=yes
	printf 'ID=debian\n' >"$R/os-release"; export BB_OS_RELEASE=$R/os-release
	: >"$R/resolv.conf"; export BB_RESOLV_FILES=$R/resolv.conf BB_SAVED_FILES=""
	# a stand-in for the built nDPId: it prints the help of the real 1.7 binary
	printf '#!/bin/sh\ncase "$1" in -h) cat "%s" ;; esac\n' "$HELP" >"$R/fake-ndpid"; chmod +x "$R/fake-ndpid"
	export BB_FAKE_NDPID=$R/fake-ndpid
	cat >"$R/stubs/systemctl" <<STUB
#!/bin/sh
echo "systemctl \$*" >>"$R/sd.log"
case "\$1" in is-enabled) exit 0 ;; is-active) exit 0 ;; esac
exit 0
STUB
	chmod +x "$R/stubs/"*
	export PATH="$R/stubs:$PATH"
}
teardown() {
	# remove exactly the users that this test's own install recorded (a user that was already there is never ours)
	local k v
	while read -r k v; do
		[ "$k" = user ] && { userdel "$v" 2>/dev/null; groupdel "$v" 2>/dev/null; }
	done <"$BB_STATE_DIR/manifest" 2>/dev/null
	teardown_root
}

has_bb_objects() { nft list tables 2>/dev/null | grep -q 'inet bb'; }
unit() { cat "$BB_UNIT_DIR/$1"; }
install_dpi() { bb install --backend nft --yes --iface lo "$@"; }

@test "install with traffic inspection: binary, users, listener settings and the three units" {
	run install_dpi
	echo "$output"
	[ "$status" -eq 0 ]
	[[ $output == *"Traffic inspection: nDPId 1.7"* ]]
	[ -x "$BB_NDPID_BIN" ]
	for u in bb bb-ndpid; do getent passwd "$u" >/dev/null; grep -qx "user $u" "$BB_STATE_DIR/manifest"; done
	[ "$(stat -c '%U:%G %a' "$BB_STATE_DIR/listener.conf")" = "root:bb 640" ]
	[ "$(stat -c '%U %a' "$BB_STATE_DIR/listener")" = "bb 700" ]
	[ "$(stat -c %a "$BB_STATE_DIR")" = 755 ]
	grep -q "^dpi='yes'" "$BB_CONF_DIR/bb.conf"
	refute grep -q 'notify\|secret' "$BB_STATE_DIR/listener.conf"       # only what the listener needs
	for u in bb-listener.socket bb-listener@.service bb-ndpid.service; do [ -s "$BB_UNIT_DIR/$u" ]; done
	grep -q 'enable bb-listener.socket bb-ndpid.service' "$R/sd.log"
	grep -q 'start bb-listener.socket bb-ndpid.service' "$R/sd.log"
}

@test "units: the socket belongs to the nDPId user (D-008), the listener has no root and only CAP_NET_ADMIN" {
	install_dpi >/dev/null
	s=$(unit bb-listener.socket)
	[[ $s == *"ListenStream=/run/bb/ndpid.sock"* && $s == *"SocketUser=bb-ndpid"* && $s == *"SocketMode=0600"* ]]
	[[ $s == *"Accept=yes"* && $s == *"MaxConnections=8"* ]]
	l=$(unit bb-listener@.service)
	[[ $l == *"User=bb"* && $l == *"StandardInput=socket"* && $l == *"AmbientCapabilities=CAP_NET_ADMIN"* && $l == *"CapabilityBoundingSet=CAP_NET_ADMIN"* ]]
	[[ $l == *"NoNewPrivileges=yes"* && $l == *"ProtectSystem=strict"* && $l == *"ReadWritePaths=-/var/lib/bb/listener"* ]]
	[[ $l != *"ReadWritePaths=/var/lib/bb "* && $l != *"User=root"* ]]
	n=$(unit bb-ndpid.service)
	[[ $n == *"User=bb-ndpid"* && $n == *"Requires=bb-listener.socket"* && $n == *"CapabilityBoundingSet=CAP_NET_RAW CAP_NET_ADMIN"* ]]
	[[ $n == *"ExecStart=$BB_NDPID_BIN -i lo -c /run/bb/ndpid.sock -u bb-ndpid -g bb-ndpid -a bb -o max-reader-threads=4"* ]]
	[[ $n == *"OnFailure=bb-notify-failure@%n.service"* ]]
	f=$(unit bb-firewall.service)
	[[ $f == *"ExecStop=$BB_BIN_PATH __save-flows"* ]]
}

@test "units: syntax and ordering of the dynamic-layer units are valid for systemd-analyze" {
	command -v systemd-analyze >/dev/null || skip "systemd-analyze not available"
	install_dpi >/dev/null
	rm -f "$BB_UNIT_DIR/bb-firewall.service.new"
	run systemd-analyze verify "$BB_UNIT_DIR"/bb-listener.socket "$BB_UNIT_DIR"/bb-ndpid.service "$BB_UNIT_DIR"/bb-listener@.service
	echo "$output"
	[ "$status" -eq 0 ]
	[[ $output != *"error"* && $output != *"cycle"* ]]
}

@test "the port mode becomes the capture filter, using the option found in the help of the build" {
	install_dpi --ports-mode only --ports 6881-6889,51413 >/dev/null
	[[ $(unit bb-ndpid.service) == *'-B "(tcp or udp) and (portrange 6881-6889 or port 51413)"'* ]]
	install_dpi --ports-mode except --ports 6881,6883-6885 >/dev/null
	[[ $(unit bb-ndpid.service) == *'-B "not (port 6881 or portrange 6883-6885)"'* ]]
	install_dpi --ports-mode all >/dev/null
	[[ $(unit bb-ndpid.service) != *" -B "* ]]
	# the option letter comes from the help, not from a constant
	sed 's/^\t-B\tSet an optional PCAP filter/\t-F\tSet an optional PCAP filter/' "$HELP" >"$R/help2"
	printf '#!/bin/sh\ncase "$1" in -h) cat "%s" ;; esac\n' "$R/help2" >"$R/fake-ndpid"
	rm -f "$BB_NDPID_BIN"
	install_dpi --ports-mode only --ports 6881 >/dev/null
	[[ $(unit bb-ndpid.service) == *'-F "(tcp or udp) and (port 6881)"'* ]]
}

@test "a build without a capture-filter option stops the install before anything changes, unless no filter is needed" {
	grep -vi 'bpf\|pcap filter' "$HELP" >"$R/help3"
	printf '#!/bin/sh\ncase "$1" in -h) cat "%s" ;; esac\n' "$R/help3" >"$R/fake-ndpid"
	run install_dpi --ports-mode only --ports 6881
	[ "$status" -ne 0 ]
	[[ $output == *"could not find the capture-filter option"* ]]
	refute has_bb_objects
	[ ! -e "$BB_UNIT_DIR/bb-ndpid.service" ]
	run getent passwd bb; [ "$status" -ne 0 ]
	run install_dpi --ports-mode all                      # no filter, so the missing option does not matter
	[ "$status" -eq 0 ]
}

@test "--no-dpi: static mode, no dynamic-layer units, users or binary; and switching back removes them" {
	run bb install --backend nft --yes --iface lo --no-dpi
	[ "$status" -eq 0 ]
	[[ $output == *"Traffic inspection is off"* ]]
	grep -q "^dpi='no'" "$BB_CONF_DIR/bb.conf"
	for u in bb-listener.socket bb-listener@.service bb-ndpid.service; do [ ! -e "$BB_UNIT_DIR/$u" ]; done
	[ ! -e "$BB_NDPID_BIN" ]
	run getent passwd bb-ndpid; [ "$status" -ne 0 ]
	install_dpi >/dev/null
	[ -s "$BB_UNIT_DIR/bb-ndpid.service" ]
	bb install --backend nft --yes --iface lo --no-dpi >/dev/null
	[ ! -e "$BB_UNIT_DIR/bb-ndpid.service" ] && [ ! -e "$BB_UNIT_DIR/bb-listener.socket" ]
	grep -q "^dpi='no'" "$BB_CONF_DIR/bb.conf"
}

# ---- the build procedure (D-007) ---------------------------------------------------------------------------
build_stubs() {
	unset BB_FAKE_NDPID
	export BB_SKIP_BUILD_DEPS=1
	cat >"$R/stubs/git" <<STUB
#!/bin/sh
echo "git \$*" >>"$R/build.log"
[ -e "$R/git.fail" ] && { echo "fatal: simulated failure" >&2; exit 128; }
case "\$1" in
	clone) for last; do :; done; mkdir -p "\$last" ;;
	-C) shift; dir=\$1; shift; case "\$1" in rev-parse) echo 9969f955dc0062582256570960277ad86f40523b ;; esac ;;
esac
exit 0
STUB
	cat >"$R/stubs/cmake" <<STUB
#!/bin/sh
echo "cmake \$*" >>"$R/build.log"
[ -e "$R/cmake.fail" ] && { echo "CMake Error: simulated" >&2; exit 1; }
exit 0
STUB
	cat >"$R/stubs/make" <<STUB
#!/bin/sh
echo "make \$*" >>"$R/build.log"
dir=.; [ "\$1" = -C ] && dir=\$2
mkdir -p "\$dir"
cp "$R/fake-ndpid" "\$dir/nDPId"; chmod +x "\$dir/nDPId"
exit 0
STUB
	chmod +x "$R/stubs/"*
}

@test "the build clones the pinned tag and initialises only libnDPI, never --recursive (D-007)" {
	build_stubs
	run install_dpi
	echo "$output"
	[ "$status" -eq 0 ]
	grep -qx 'git clone --depth 1 --branch 1.7 https://github.com/utoni/nDPId.git '"$BB_STATE_DIR"'/tmp.*/ndpid' <(sed "s|$BB_STATE_DIR/tmp\.[A-Za-z0-9]*/|$BB_STATE_DIR/tmp.X/|; s|tmp\.X|tmp.*|" "$R/build.log") || grep -q 'git clone --depth 1 --branch 1.7 https://github.com/utoni/nDPId.git' "$R/build.log"
	grep -q 'submodule update --init --depth 1 libnDPI' "$R/build.log"
	refute grep -q -e '--recursive' -e 'recurse' "$R/build.log"
	grep -q 'cmake -S .* -B .* -DBUILD_NDPI=ON -DBUILD_EXAMPLES=OFF' "$R/build.log"
	grep -q 'make -C .*/build -j' "$R/build.log"
	[ -x "$BB_NDPID_BIN" ]
	[ "$(cut -d' ' -f1 "$BB_STATE_DIR/ndpid.version")" = 1.7 ]
	[ "$(cut -d' ' -f2 "$BB_STATE_DIR/ndpid.version")" = 9969f955dc0062582256570960277ad86f40523b ]
}

@test "a reference that is a commit is cloned in full and checked out" {
	build_stubs
	NDPID_REF=9969f955dc0062582256570960277ad86f40523b run install_dpi
	[ "$status" -eq 0 ]
	grep -q 'git clone https://github.com/utoni/nDPId.git' "$R/build.log"
	refute grep -q -- '--branch' "$R/build.log"
	grep -q 'checkout -q 9969f955dc0062582256570960277ad86f40523b' "$R/build.log"
}

@test "an installed nDPId is not built again" {
	build_stubs
	install_dpi >/dev/null
	: >"$R/build.log"
	run install_dpi
	[[ $output == *"nDPId is already installed; skipping the build."* ]]
	[ ! -s "$R/build.log" ]
}

@test "a failed build leaves the firewall, the configuration and the users untouched and says how to go on" {
	build_stubs
	touch "$R/cmake.fail"
	run install_dpi
	[ "$status" -ne 0 ]
	[[ $output == *"building nDPId failed; the firewall was not changed"* && $output == *"--no-dpi"* && $output == *"$BB_STATE_DIR/dpi-build.log"* ]]
	grep -q 'CMake Error: simulated' "$BB_STATE_DIR/dpi-build.log"      # the reason is in the log
	refute has_bb_objects
	[ ! -e "$BB_CONF_DIR/bb.conf" ] && [ ! -e "$BB_UNIT_DIR/bb-firewall.service" ] && [ ! -e "$BB_NDPID_BIN" ]
	run getent passwd bb; [ "$status" -ne 0 ]
	rm "$R/cmake.fail"; touch "$R/git.fail"
	run install_dpi
	[ "$status" -ne 0 ]
	refute has_bb_objects
	run bb install --backend nft --yes --iface lo --no-dpi                # the advice works
	[ "$status" -eq 0 ]
}

@test "build packages are installed and recorded, jq is added only for the listener, and uninstall takes them back" {
	pkg_stubs apt; printf 'jq\n' >"$R/absent"
	build_stubs; unset BB_SKIP_BUILD_DEPS
	run install_dpi
	echo "$output"
	[ "$status" -eq 0 ]
	grep -q 'apt-get install -y jq' "$R/pkg.log"
	grep -q 'apt-get install -y build-essential git cmake' "$R/pkg.log"
	grep -qx 'pkg apt:cmake' "$BB_STATE_DIR/manifest"
	grep -qx 'pkg apt:build-essential-deps' "$BB_STATE_DIR/manifest"
	run bb uninstall --yes
	[ "$status" -eq 0 ]
	grep -q 'apt-get purge -y -- ' "$R/pkg.log"
	[ "$(cat "$R/pkgs.state")" = libpreexisting ]
}

@test "uninstall removes the dynamic layer: units, binary, users, runtime directory; a user that was already there stays" {
	useradd --system --no-create-home --shell /usr/sbin/nologin bb 2>/dev/null || true
	install_dpi >/dev/null
	! grep -qx 'user bb' "$BB_STATE_DIR/manifest"                            # it existed before, so it is not ours
	grep -qx 'user bb-ndpid' "$BB_STATE_DIR/manifest"
	mkdir -p "$R/run"; touch "$R/run/ndpid.sock"
	run bb uninstall --yes
	[ "$status" -eq 0 ]
	for u in bb-listener.socket bb-listener@.service bb-ndpid.service bb-firewall.service; do [ ! -e "$BB_UNIT_DIR/$u" ]; done
	[ ! -e "$BB_NDPID_BIN" ] && [ ! -e "$R/run" ] && [ ! -e "$BB_STATE_DIR" ]
	run getent passwd bb-ndpid; [ "$status" -ne 0 ]
	getent passwd bb >/dev/null                                               # left alone
	grep -qF 'stop bb-listener@*.service' "$R/sd.log"
	userdel bb 2>/dev/null || true; groupdel bb 2>/dev/null || true
}

@test "bb doctor checks the dynamic layer" {
	install_dpi >/dev/null
	run bb doctor
	echo "$output"
	[ "$status" -eq 0 ]
	[[ $output == *"[  ok] nDPId 1.7"* || $output == *"[  ok] nDPId ?"* ]]
	[[ $output == *"jq is installed"* && $output == *"unit bb-listener.socket is enabled"* && $output == *"listener.conf belongs to root:bb with mode 0640"* ]]
	chmod 644 "$BB_STATE_DIR/listener.conf"
	run bb doctor; [ "$status" -eq 1 ]
	[[ $output == *"[FAIL] listener.conf must belong to root:bb with mode 0640"* ]]
	chmod 640 "$BB_STATE_DIR/listener.conf"
	rm "$BB_NDPID_BIN"
	run bb doctor; [ "$status" -eq 1 ]
	[[ $output == *"[FAIL] nDPId is missing or does not start"* ]]
	printf 'jq\n' >"$R/absent"
	BB_TEST_ABSENT_FILE=$R/absent run bb doctor
	[[ $output == *"[FAIL] jq is missing"* ]]
}

@test "the listener runs as an unprivileged user with CAP_NET_ADMIN and nothing else (D-009)" {
	command -v setpriv >/dev/null || skip "setpriv not available"
	install_dpi >/dev/null
	# make the scratch tree readable for the user bb, except what must stay private
	rm -rf "$R/share2"; mkdir -p "$R/share2"; cp -r "$REPO/lang" "$REPO/src/net.awk" "$R/share2/"
	cp "$REPO/src/bb" "$R/sbin/bb-real"; chmod 755 "$R/sbin/bb-real"
	chmod 755 "$R" "$R/sbin" "$R/share2"; chmod -R a+rX "$R/share2"
	chmod 700 "$BB_CONF_DIR"                                                 # bb.conf stays root-only
	chmod 755 "$(dirname "$BB_STATE_DIR")" 2>/dev/null
	run_as_bb() { setpriv --reuid=bb --regid=bb --clear-groups --inh-caps=-all,+net_admin --ambient-caps=+net_admin --bounding-set=-all,+net_admin "$@"; }
	run run_as_bb grep CapEff /proc/self/status
	[[ $output == *"0000000000001000"* ]]                                    # exactly CAP_NET_ADMIN
	run run_as_bb cat "$BB_CONF_DIR/bb.conf"; [ "$status" -ne 0 ]            # cannot read the configuration
	run run_as_bb touch "$BB_STATE_DIR/x"; [ "$status" -ne 0 ]               # cannot write the state directory
	run run_as_bb touch "$BB_STATE_DIR/listener/x"; [ "$status" -eq 0 ]      # only its own directory
	BB_SHARE_DIR=$R/share2 run_as_bb env BB_TESTING=1 BB_CONF_DIR="$BB_CONF_DIR" BB_STATE_DIR="$BB_STATE_DIR" BB_BACKUP_DIR="$BB_BACKUP_DIR" \
		BB_LOCK_FILE="$BB_LOCK_FILE" BB_SHARE_DIR="$R/share2" BB_UNIT_DIR="$BB_UNIT_DIR" LC_ALL=C "$R/sbin/bb-real" __listener <"$FIX"
	nft get element inet bb flow4 "{ 203.0.113.10 . 41000 . 198.51.100.20 . 6881 }" >/dev/null   # flows were added by an unprivileged process
	nft get element inet bb flow6 "{ 2001:db8::10 . 42000 . 2001:db8:1::20 . 6881 }" >/dev/null
}

# several interfaces: one nDPId process each
@test "several interfaces: the first is bb-ndpid.service, the others are instances that belong to it" {
	run bb install --backend nft --yes --iface lo,eth1,eth2
	echo "$output"
	[ "$status" -eq 0 ]
	grep -q "^iface='lo eth1 eth2'" "$BB_CONF_DIR/bb.conf"
	n=$(unit bb-ndpid.service)
	[[ $n == *"ExecStart=$BB_NDPID_BIN -i lo -c /run/bb/ndpid.sock -u bb-ndpid -g bb-ndpid -a bb -o max-reader-threads=4"* ]]
	[[ $n == *"Wants=bb-ndpid@eth1.service bb-ndpid@eth2.service"* ]]
	t=$(unit 'bb-ndpid@.service')
	[[ $t == *"PartOf=bb-ndpid.service"* && $t == *"Requires=bb-listener.socket"* && $t == *"User=bb-ndpid"* ]]
	[[ $t == *"ExecStart=$BB_NDPID_BIN -i %i -c /run/bb/ndpid.sock -u bb-ndpid -g bb-ndpid -a bb-%i -o max-reader-threads=4"* ]]
	[[ $t == *"CapabilityBoundingSet=CAP_NET_RAW CAP_NET_ADMIN"* ]]
	# every nDPId process opens up to 4 connections: 4 per interface and 4 spare
	[[ $(unit bb-listener.socket) == *"MaxConnections=16"* ]]
	if command -v systemd-analyze >/dev/null; then
		rm -f "$BB_UNIT_DIR"/*.new
		run systemd-analyze verify "$BB_UNIT_DIR"/bb-listener.socket "$BB_UNIT_DIR"/bb-ndpid.service "$BB_UNIT_DIR"/bb-ndpid@.service "$BB_UNIT_DIR"/bb-listener@.service
		echo "$output"; [[ $output != *"error"* && $output != *"cycle"* ]]
	fi
}

@test "one interface: no instance unit, no Wants line, the usual connection limit" {
	install_dpi >/dev/null
	[ ! -e "$BB_UNIT_DIR/bb-ndpid@.service" ]
	[[ $(unit bb-ndpid.service) != *"bb-ndpid@"* ]]
	[[ $(unit bb-listener.socket) == *"MaxConnections=8"* ]]
}

@test "several interfaces: the list is validated and commas are accepted" {
	run bb install --backend nft --yes --iface 'lo;eth1'; [ "$status" -ne 0 ]
	run bb install --backend nft --yes --iface 'eth0@if3'; [ "$status" -ne 0 ]
	run bb install --backend nft --yes --iface 'a,b,c,d,e,f,g,h,i'; [ "$status" -ne 0 ]
	[ ! -e "$BB_CONF_DIR/bb.conf" ] || ! grep -q '^backend=' "$BB_CONF_DIR/bb.conf"
	run bb install --backend nft --yes --iface 'lo, eth1'; [ "$status" -eq 0 ]
	grep -q "^iface='lo eth1'" "$BB_CONF_DIR/bb.conf"
}

@test "several interfaces: an interface taken out of the list is stopped; uninstall stops all instances" {
	cat >"$R/stubs/systemctl" <<STUB
#!/bin/sh
echo "systemctl \$*" >>"$R/sd.log"
case "\$1" in list-units) printf 'bb-ndpid@eth1.service loaded active running x\nbb-ndpid@eth2.service loaded active running x\n' ;; is-enabled|is-active) exit 0 ;; esac
exit 0
STUB
	bb install --backend nft --yes --iface lo,eth1,eth2 >/dev/null
	: >"$R/sd.log"
	bb install --backend nft --yes --force --iface lo,eth1 >/dev/null
	grep -q 'stop bb-ndpid@eth2.service' "$R/sd.log"
	! grep -q 'stop bb-ndpid@eth1.service' "$R/sd.log"
	: >"$R/sd.log"
	run bb uninstall --yes
	[ "$status" -eq 0 ]
	grep -q "stop bb-listener@\*.service bb-ndpid@\*.service" "$R/sd.log"
	[ ! -e "$BB_UNIT_DIR/bb-ndpid@.service" ]
}

@test "doctor checks every interface of nDPId and the instance of each extra one" {
	bb install --backend nft --yes --iface lo,nosuch0 >/dev/null
	cat >"$R/stubs/systemctl" <<STUB
#!/bin/sh
case "\$1" in is-active) case "\$3" in bb-ndpid@nosuch0.service) exit 3 ;; esac ;; esac
exit 0
STUB
	run bb doctor --json
	jq -e '([.checks[] | select(.id == "dpi_iface_ok")][0].args == ["lo"])
		and ([.checks[] | select(.id == "dpi_iface_missing")][0].args == ["nosuch0"])
		and ([.checks[] | select(.id == "dpi_iface_stopped")][0].args == ["nosuch0"])' <<<"$output" >/dev/null
}
