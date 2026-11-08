# bb network-entry normalizer (POSIX awk: works with mawk and gawk).
# Input : free-form lines (IP, CIDR, host name, URL), '#' comments allowed.
# Output: "4<TAB>canon", "6<TAB>canon" or "H<TAB>host" on stdout.
# Stats : written to the file given in -v stats=FILE.
# Vars  : strip=1  drop private/special-purpose ranges
#         minp4/minp6  minimum prefix accepted (too broad -> rejected)
#         hosts=1  pass host names through ("H" records), otherwise invalid
#         orig=1   append the input token as a third column ("4<TAB>canon<TAB>input")

function hexval(h,   i, c, v, d) {
	v = 0; h = tolower(h)
	if (h == "" || length(h) > 4) return -1
	for (i = 1; i <= length(h); i++) {
		c = substr(h, i, 1); d = index("0123456789abcdef", c) - 1
		if (d < 0) return -1
		v = v * 16 + d
	}
	return v
}

function pow2(n,   r) { r = 1; while (n-- > 0) r *= 2; return r }

# ---- IPv4 -----------------------------------------------------------------
function v4int(s,   n, a, i) {
	n = split(s, a, ".")
	if (n != 4) return -1
	for (i = 1; i <= 4; i++) {
		if (a[i] !~ /^[0-9]+$/ || length(a[i]) > 3) return -1
		if (length(a[i]) > 1 && substr(a[i], 1, 1) == "0") return -1
		if (a[i] + 0 > 255) return -1
	}
	return ((a[1] * 256 + a[2]) * 256 + a[3]) * 256 + a[4]
}

function v4str(n,   a, b, c, d) {
	d = n % 256; n = (n - d) / 256
	c = n % 256; n = (n - c) / 256
	b = n % 256; a = (n - b) / 256
	return a "." b "." c "." d
}

function inside4(net, p, rnet, rp) {
	if (p < rp) return 0
	return (net - net % pow2(32 - rp)) == rnet
}

function private4(net, p,   i) {
	for (i = 1; i <= NR4; i++) if (inside4(net, p, R4N[i], R4P[i])) return 1
	return 0
}

# ---- IPv6 -----------------------------------------------------------------
# parse into G[1..8]; returns 1 on success
function v6parse(s, G,   t, n, a, i, k, tail, v, left, right, nl, nr, L, R, ds) {
	s = tolower(s)
	if (s !~ /^[0-9a-f:.]+$/ || index(s, ":") == 0) return 0
	if (index(s, ":::") > 0) return 0
	ds = 0; t = s
	while ((i = index(t, "::")) > 0) { ds++; t = substr(t, i + 2); if (ds > 1) return 0 }
	i = index(s, "::")
	if (i > 0) { left = substr(s, 1, i - 1); right = substr(s, i + 2) }
	else { left = s; right = "" }
	nl = (left == "") ? 0 : split(left, L, ":")
	nr = (right == "") ? 0 : split(right, R, ":")
	if (i == 0) { nr = 0 }
	# embedded IPv4 tail: last token of the last part
	tail = 0
	if (i > 0 && nr > 0) { if (index(R[nr], ".") > 0) { v = v4int(R[nr]); if (v < 0) return 0; R[nr] = sprintf("%x", int(v / 65536)); R[++nr] = sprintf("%x", v % 65536); tail = 1 } }
	else if (i == 0 && nl > 0) { if (index(L[nl], ".") > 0) { v = v4int(L[nl]); if (v < 0) return 0; L[nl] = sprintf("%x", int(v / 65536)); L[++nl] = sprintf("%x", v % 65536); tail = 1 } }
	for (k = 1; k <= nl; k++) if (index(L[k], ".") > 0) return 0
	for (k = 1; k <= nr; k++) if (index(R[k], ".") > 0) return 0
	if (i == 0) { if (nl != 8) return 0 }
	else { if (nl + nr > 7) return 0 }
	for (k = 1; k <= 8; k++) G[k] = 0
	for (k = 1; k <= nl; k++) { v = hexval(L[k]); if (v < 0) return 0; G[k] = v }
	for (k = 1; k <= nr; k++) { v = hexval(R[k]); if (v < 0) return 0; G[8 - nr + k] = v }
	return 1
}

function v6mask(G, p, M,   k, keep) {
	for (k = 1; k <= 8; k++) {
		if (p >= k * 16) M[k] = G[k]
		else if (p <= (k - 1) * 16) M[k] = 0
		else { keep = p - (k - 1) * 16; M[k] = G[k] - G[k] % pow2(16 - keep) }
	}
}

function v6str(G,   k, best, bl, cur, cs, s, st) {
	best = 0; bl = 0; cur = 0; cs = 0
	for (k = 1; k <= 8; k++) {
		if (G[k] == 0) { if (cur == 0) cs = k; cur++; if (cur > bl) { bl = cur; best = cs } }
		else cur = 0
	}
	if (bl < 2) best = 0
	s = ""
	for (k = 1; k <= 8; k++) {
		if (best > 0 && k == best) { s = s "::"; k += bl - 1; continue }
		if (s != "" && substr(s, length(s)) != ":") s = s ":"
		s = s sprintf("%x", G[k])
	}
	return s
}




function setup(   i, k, G, n, a) {
	# IPv4 special-purpose ranges
	n = 0
	R4N[++n] = v4int("0.0.0.0");     R4P[n] = 8
	R4N[++n] = v4int("10.0.0.0");    R4P[n] = 8
	R4N[++n] = v4int("100.64.0.0");  R4P[n] = 10
	R4N[++n] = v4int("127.0.0.0");   R4P[n] = 8
	R4N[++n] = v4int("169.254.0.0"); R4P[n] = 16
	R4N[++n] = v4int("172.16.0.0");  R4P[n] = 12
	R4N[++n] = v4int("192.0.0.0");   R4P[n] = 24
	R4N[++n] = v4int("192.168.0.0"); R4P[n] = 16
	R4N[++n] = v4int("198.18.0.0");  R4P[n] = 15
	R4N[++n] = v4int("224.0.0.0");   R4P[n] = 4
	R4N[++n] = v4int("240.0.0.0");   R4P[n] = 4
	NR4 = n
	# IPv6 special-purpose ranges (stored as flat arrays of groups)
	n = 0
	split("0 0 0 0 0 0 0 0", a, " ");       n++; for (k = 1; k <= 8; k++) RG[n, k] = a[k]; R6P[n] = 128
	split("0 0 0 0 0 0 0 1", a, " ");       n++; for (k = 1; k <= 8; k++) RG[n, k] = a[k]; R6P[n] = 128
	split("0 0 0 0 0 65535 0 0", a, " ");   n++; for (k = 1; k <= 8; k++) RG[n, k] = a[k]; R6P[n] = 96
	split("64512 0 0 0 0 0 0 0", a, " ");   n++; for (k = 1; k <= 8; k++) RG[n, k] = a[k]; R6P[n] = 7
	split("65152 0 0 0 0 0 0 0", a, " ");   n++; for (k = 1; k <= 8; k++) RG[n, k] = a[k]; R6P[n] = 10
	split("65280 0 0 0 0 0 0 0", a, " ");   n++; for (k = 1; k <= 8; k++) RG[n, k] = a[k]; R6P[n] = 8
	NR6 = n
}

function private6(G, p,   i, k, M, ok) {
	for (i = 1; i <= NR6; i++) {
		if (p < R6P[i]) continue
		v6mask(G, R6P[i], M)
		ok = 1
		for (k = 1; k <= 8; k++) if (M[k] != RG[i, k]) { ok = 0; break }
		if (ok) return 1
	}
	return 0
}

function bump(k) { ST[k]++ }

# Normalize one token. Prints a record, updates stats.
function handle(tok,   addr, plen, pos, G, M, n, net, c, host, h, pfx) {
	pos = index(tok, "/")
	if (pos > 0) { addr = substr(tok, 1, pos - 1); plen = substr(tok, pos + 1); if (plen !~ /^[0-9]+$/ || length(plen) > 3) { bump("invalid"); return } plen += 0 }
	else { addr = tok; plen = -1 }
	if (addr ~ /^[0-9.]+$/) {
		n = v4int(addr)
		if (n < 0) { bump("invalid"); return }
		if (plen < 0) plen = 32
		if (plen > 32) { bump("invalid"); return }
		if (plen < minp4) { bump("broad"); return }
		net = n - n % pow2(32 - plen)
		if (strip && private4(net, plen)) { bump("private"); return }
		c = v4str(net) ((plen < 32) ? "/" plen : "")
		if (c in seen) { bump("dup"); return }
		seen[c] = 1; bump("ok"); print "4\t" c (orig ? "\t" tok : "")
		return
	}
	if (index(addr, ":") > 0) {
		if (!v6parse(addr, G)) { bump("invalid"); return }
		if (plen < 0) plen = 128
		if (plen > 128) { bump("invalid"); return }
		if (plen < minp6) { bump("broad"); return }
		v6mask(G, plen, M)
		if (strip && private6(M, plen)) { bump("private"); return }
		c = v6str(M) ((plen < 128) ? "/" plen : "")
		if (c in seen) { bump("dup"); return }
		seen[c] = 1; bump("ok"); print "6\t" c (orig ? "\t" tok : "")
		return
	}
	# host name
	if (pos == 0 && hosts && tok ~ /^[A-Za-z0-9]([A-Za-z0-9_.-]*[A-Za-z0-9])?$/ && tok ~ /[A-Za-z]/ && tok ~ /\./ && length(tok) <= 253) {
		h = tolower(tok)
		if (h in seenh) { bump("dup"); return }
		seenh[h] = 1; bump("hosts"); print "H\t" h
		return
	}
	bump("invalid")
}

BEGIN { setup(); if (minp4 == "") minp4 = 0; if (minp6 == "") minp6 = 0; minp4 += 0; minp6 += 0 }

{
	line = $0
	sub(/\r$/, "", line)
	sub(/#.*/, "", line)
	gsub(/^[ \t]+|[ \t]+$/, "", line)
	if (line == "") next
	split(line, F, /[ \t,;]+/)
	tok = F[1]
	# URL form: scheme://[user@]host[:port][/path]
	if (tok ~ /^[A-Za-z][A-Za-z0-9+.-]*:\/\//) {
		sub(/^[A-Za-z][A-Za-z0-9+.-]*:\/\//, "", tok)
		sub(/[\/?].*$/, "", tok)
		sub(/^[^@]*@/, "", tok)
		if (substr(tok, 1, 1) == "[") { sub(/^\[/, "", tok); sub(/\].*$/, "", tok) }
		else if (tok ~ /^[^:]*:[0-9]*$/) sub(/:[0-9]*$/, "", tok)
	}
	handle(tok)
}

END {
	if (stats != "") {
		printf "ok=%d invalid=%d private=%d broad=%d dup=%d hosts=%d\n", ST["ok"], ST["invalid"], ST["private"], ST["broad"], ST["dup"], ST["hosts"] > stats
		close(stats)
	}
}
