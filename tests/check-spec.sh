#!/usr/bin/env bash
# Verifies tech.md against the repository (run by tests/run.sh and `make spec`).
#   - slices (section 17): numbering, status table, and that every [x] criterion cites a test
#     that exists, by file and by a substring of the test name;
#   - deviation register (section 18): IDs, spec sections, tests, and anchors in the code.
# Usage: check-spec.sh [--table] [path-to-tech.md]   (--table prints the computed status table)
set -u
cd "$(dirname "$0")/.." || exit 1
mode=check
[[ ${1:-} == --table ]] && { mode=table; shift; }
SPEC=${1:-tech.md}
fail=0
err() { printf 'check-spec: %s\n' "$*"; fail=1; }

[[ -r $SPEC ]] || { echo "check-spec: cannot read $SPEC"; exit 1; }
grep -qE '^\*\*Version: v[0-9]+\*\*' "$SPEC" || err "missing '**Version: vN**' line"
grep -qE '^\*\*Status: ' "$SPEC" || err "missing '**Status: ...**' line"
if grep -n '{{' "$SPEC" >/dev/null; then err "unresolved '{{' placeholder"; fi

# ---- 1. parse the spec into flat records -------------------------------------------------
records=$(awk '
	/^## 17\./ { sec = "slices"; next }
	/^## 18\./ { sec = "dev"; next }
	/^## / { sec = ""; next }
	function refs(id, line,    r) {
		while (match(line, /\(tests\/[A-Za-z0-9_.-]+: [^)]*\)/)) {
			r = substr(line, RSTART + 1, RLENGTH - 2)
			i = index(r, ": ")
			print "REF\t" id "\t" substr(r, 1, i - 1) "\t" substr(r, i + 2)
			line = substr(line, RSTART + RLENGTH)
		}
	}
	sec == "slices" && /^### Slice / {
		lab = $3; sub(/:$/, "", lab)
		title = $0; sub(/^### Slice [^:]*: */, "", title); t = title; gsub(/ /, "", t)
		print "SLICE\t" lab "\t" t "\t" title; next
	}
	sec == "slices" && /^[0-9]+\. \[(x|~| )\] \*\*S/ {
		n = $1; sub(/\.$/, "", n)
		match($0, /\[(x|~| )\]/); mark = substr($0, RSTART + 1, 1)
		match($0, /\*\*S[0-9A-Z]+\.[0-9]+\*\*/); id = substr($0, RSTART + 2, RLENGTH - 4)
		print "CRIT\t" lab "\t" n "\t" mark "\t" id
		refs(id, $0)
		if ($0 ~ /\(manual\)/) print "MANUAL\t" id
		next
	}
	sec == "slices" && /^\| S[0-9A-Z]+ \|/ {
		gsub(/ /, ""); split($0, c, "|"); print "ROW\t" substr(c[2], 2) "\t" c[3] "\t" c[4] "\t" c[5]; next
	}
	sec == "dev" && /^\| D-[0-9][0-9][0-9] \|/ {
		split($0, c, "|"); id = c[2]; gsub(/ /, "", id); st = c[6]; gsub(/ /, "", st)
		sp = c[3]; gsub(/ /, "", sp)
		print "DEV\t" id "\t" sp "\t" st
		refs(id, $0)
	}
' "$SPEC")

# ---- 2. slices ---------------------------------------------------------------------------------
declare -A total done partial seen_id stitle sorig
slices=()
while IFS=$'\t' read -r kind a b c d; do
	case $kind in
		SLICE)
			stitle[$a]=$b sorig[$a]=$c
			[[ $a =~ ^[0-9A-Z]+$ ]] || err "bad slice label '$a'"
			[[ -v total[$a] ]] && err "duplicate slice $a"
			total[$a]=0 done[$a]=0 partial[$a]=0
			slices+=("$a") ;;
		CRIT)
			# a=slice b=number c=mark d=id
			[[ $d == "S$a.$b" ]] || err "criterion '$d' should be S$a.$b (slice $a, item $b)"
			[[ -v seen_id[$d] ]] && err "duplicate criterion $d"
			seen_id[$d]=1
			total[$a]=$((${total[$a]} + 1))
			[[ $c == x ]] && done[$a]=$((${done[$a]} + 1))
			[[ $c == '~' ]] && partial[$a]=$((${partial[$a]} + 1)) ;;
	esac
done <<<"$records"

# every [x] needs a verified reference (or an explicit manual check)
declare -A has_ref is_manual
while IFS=$'\t' read -r kind a b c d; do
	[[ $kind == REF ]] && has_ref[$a]=1
	[[ $kind == MANUAL ]] && is_manual[$a]=1
done <<<"$records"
while IFS=$'\t' read -r kind a b c d; do
	[[ $kind == CRIT && $c == x ]] || continue
	[[ -v has_ref[$d] || -v is_manual[$d] ]] || err "$d is marked [x] but cites no test and is not (manual)"
done <<<"$records"

# every cited test must exist: file and a literal substring of a test name
while IFS=$'\t' read -r kind id file text; do
	[[ $kind == REF ]] || continue
	if [[ ! -f $file ]]; then err "$id cites $file, which does not exist"
	elif ! grep -qF -- "$text" "$file"; then err "$id cites '$text' in $file, which is not there"; fi
done <<<"$records"

# computed status table
computed=""
for s in "${slices[@]}"; do
	st=remaining
	if ((${done[$s]} == ${total[$s]} && ${total[$s]} > 0)); then st=done
	elif ((${done[$s]} + ${partial[$s]} > 0)); then st=partial; fi
	computed+="S$s ${stitle[$s]} $st ${done[$s]}/${total[$s]}"$'\n'
done
if [[ $mode == table ]]; then
	for s in "${slices[@]}"; do
		st=$(grep -E "^S$s " <<<"$computed" | cut -d' ' -f3)
		c=$(grep -E "^S$s " <<<"$computed" | cut -d' ' -f4)
		printf '| S%s | %s | %s | %s |\n' "$s" "${sorig[$s]}" "$st" "$c"
	done
	exit 0
fi
declared=$(while IFS=$'\t' read -r kind a b c d; do [[ $kind == ROW ]] && printf 'S%s %s %s %s\n' "$a" "$b" "$c" "$d"; done <<<"$records")
if [[ $(printf '%s' "$computed") != "$declared" ]]; then
	err "the status table in section 17 does not match the criteria or the slice titles; run tests/check-spec.sh --table"
fi

# ---- 3. deviation register ------------------------------------------------------------------------
declare -A dev_seen
prev=0
while IFS=$'\t' read -r kind id spec st; do
	[[ $kind == DEV ]] || continue
	[[ -v dev_seen[$id] ]] && err "duplicate deviation $id"
	dev_seen[$id]=1
	num=$((10#${id#D-}))
	((num == prev + 1)) || err "deviation IDs must be sequential: $id follows D-$(printf '%03d' "$prev")"
	prev=$num
	[[ $st == active || $st == resolved ]] || err "$id: status must be active or resolved (found '$st')"
	# the spec sections it names must exist as headings
	for sec in $(grep -oE '§[0-9]+(\.[0-9]+)?' <<<"$spec" | tr -d '§'); do
		grep -qE "^#{2,3} $sec\." "$SPEC" || err "$id names section $sec, which does not exist"
	done
	[[ -n $spec ]] || err "$id: the Spec column is empty"
	if [[ $st == active ]]; then
		[[ $(grep -c "(see $id)" "$SPEC") -ge 1 ]] || err "$id is active but the spec text never says '(see $id)' where it applies"
		grep -qP "^REF\t$id\t" <<<"$records" || err "$id is active but cites no test"
		grep -rqF -- "$id" src >/dev/null 2>&1 || grep -rqF --exclude=spec.bats --exclude=check-spec.sh -- "$id" tests || err "$id is not anchored anywhere in src/ or tests/ (add '# $id' at the code that deviates)"
	fi
done <<<"$records"
# ...and no code may mention a deviation that is not registered
while IFS= read -r ref; do
	[[ -v dev_seen[$ref] ]] || err "$ref is referenced in the repository but not in the register"
done < <(grep -rhoE 'D-[0-9]{3}' src lang tests README.md Makefile --exclude=spec.bats --exclude=check-spec.sh 2>/dev/null | sort -u)

exit "$fail"
