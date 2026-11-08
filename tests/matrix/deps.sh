#!/usr/bin/env bash
# Installs what the suite needs on a Debian/Ubuntu or RHEL-family container. Used by CI only.
set -eu
if command -v apt-get >/dev/null; then
	export DEBIAN_FRONTEND=noninteractive
	apt-get update -qq
	apt-get install -y -qq bats jq shellcheck nftables iptables ipset socat iproute2 util-linux iputils-ping netcat-openbsd curl wget make git
else
	dnf install -y epel-release 2>/dev/null || true
	dnf install -y --allowerasing bats jq ShellCheck nftables iptables-nft ipset socat iproute util-linux iputils nmap-ncat curl wget make git
fi
