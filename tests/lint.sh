#!/usr/bin/env bash
# Static checks: catalog parity and "no hard-coded user-visible strings".
cd "$(dirname "$0")/.." || exit 1
fail=0

keys_of() { ( declare -A MSG=(); source "$1"; for k in "${!MSG[@]}"; do printf '%s\0%s\0' "$k" "${MSG[$k]}"; done ); }
phs() { grep -o '%[-0-9.]*[sdxo]' <<<"$1" | tr -d '\n'; }

declare -A EN RU
while IFS= read -r -d '' k && IFS= read -r -d '' v; do EN[$k]=$v; done < <(keys_of lang/en.sh)
while IFS= read -r -d '' k && IFS= read -r -d '' v; do RU[$k]=$v; done < <(keys_of lang/ru.sh)

for k in "${!EN[@]}"; do
	if [[ ! -v RU[$k] ]]; then echo "lint: key '$k' missing in ru.sh"; fail=1; continue; fi
	[[ $(phs "${EN[$k]}") == "$(phs "${RU[$k]}")" ]] || { echo "lint: placeholder mismatch for '$k'"; fail=1; }
done
for k in "${!RU[@]}"; do [[ -v EN[$k] ]] || { echo "lint: key '$k' only in ru.sh"; fail=1; }; done

# Every key used by the script must exist in the catalog.
used=$(grep -oE '\b(say|warn|err|die)[[:space:]]+"?[a-z][a-z0-9_]+' src/bb | awk '{ print $2 }' | tr -d '"' | sort -u)
for k in $used; do
	[[ -v EN[$k] ]] && continue
	# dynamic keys (help_$topic, status_rules_$state) are checked by prefix
	[[ $k == help_ || $k == status_rules_ ]] && continue
	echo "lint: key '$k' used in src/bb but missing from en.sh"; fail=1
done
for k in status_rules_present status_rules_absent; do [[ -v EN[$k] ]] || { echo "lint: $k missing"; fail=1; }; done

# No literal sentences passed to say/warn/err/die.
if grep -nE '\b(say|warn|err|die)[[:space:]]+"[^"$]*[ A-Z]' src/bb | grep -v 'bb-lint: ok'; then
	echo "lint: hard-coded user-visible string (use the catalog)"; fail=1
fi
# no interpreters: the product is bash plus standard tools (no Python, Perl, Ruby, Node)
if grep -nE '^[^#]*\b(python3?|perl|ruby|node)\b[[:space:]]+[-A-Za-z./]' src/bb src/net.awk 2>/dev/null | grep -v 'bb-lint: ok'; then
	echo "lint: no interpreters are allowed in the product"; fail=1
fi
[[ $(head -1 src/bb) == '#!/usr/bin/env bash' ]] || { echo "lint: src/bb must be a bash script"; fail=1; }
exit $fail
