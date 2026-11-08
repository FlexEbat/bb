#!/usr/bin/env bash
# Checks CHANGELOG.md (Keep a Changelog) and, given a tag, that tag, version and changelog agree.
# Usage: check-release.sh [vX.Y.Z]   (run by tests/spec.bats and by the release workflow)
set -u
cd "$(dirname "$0")/.." || exit 1
fail=0
err() { printf 'check-release: %s\n' "$*"; fail=1; }
CL=${BB_CHANGELOG:-CHANGELOG.md}
SRC=${BB_SOURCE:-src/bb}

[[ -r $CL ]] || { echo "check-release: cannot read $CL"; exit 1; }
head -1 "$CL" | grep -qx '# Changelog' || err "the first line must be '# Changelog'"
grep -q 'keepachangelog.com' "$CL" || err "the header must refer to Keep a Changelog"
grep -q 'semver.org' "$CL" || err "the header must refer to Semantic Versioning"
grep -qx '## \[Unreleased\]' "$CL" || err "missing the '## [Unreleased]' section"

# every version heading: ## [X.Y.Z] - YYYY-MM-DD, newest first, each with a valid kind of change
prev=""
while IFS= read -r h; do
	[[ $h =~ ^##\ \[([0-9]+\.[0-9]+\.[0-9]+)\]\ -\ ([0-9]{4}-[0-9]{2}-[0-9]{2})$ ]] || { err "bad version heading: $h"; continue; }
	v=${BASH_REMATCH[1]}
	if [[ -n $prev && $(printf '%s\n%s\n' "$v" "$prev" | sort -V | head -1) != "$v" ]]; then err "versions must be newest first: $v after $prev"; fi
	prev=$v
done < <(grep -E '^## \[[0-9]' "$CL"; grep -E '^## [^\[]' "$CL")
while IFS= read -r h; do
	case ${h#\#\#\# } in Added | Changed | Deprecated | Removed | Fixed | Security) ;; *) err "unknown kind of change: $h" ;; esac
done < <(grep -E '^### ' "$CL")

ver=$(sed -n 's/^BB_VERSION="\(.*\)"$/\1/p' "$SRC")
[[ -n $ver ]] || err "cannot read BB_VERSION from $SRC"

if (($# > 0)); then
	tag=$1
	[[ $tag =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]] || { err "the tag must look like vX.Y.Z (got '$tag')"; exit 1; }
	want=${BASH_REMATCH[1]}
	[[ $ver == "$want" ]] || err "tag $tag does not match BB_VERSION=$ver in $SRC"
	grep -qE "^## \[$want\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$" "$CL" || err "CHANGELOG.md has no dated section for $want"
else
	[[ $ver =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] || err "BB_VERSION '$ver' is not a semantic version"
fi
exit $fail
