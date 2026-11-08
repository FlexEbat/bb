#!/usr/bin/env bats
load helpers

setup() { R=$(mktemp -d); }
teardown() { rm -rf "$R"; }

# a scratch copy of the repository, so the checker can be fed broken input
mk_repo() {
	mkdir -p "$R/repo"
	cp -r "$REPO"/src "$REPO"/lang "$REPO"/tests "$REPO"/tech.md "$REPO"/README.md "$REPO"/Makefile "$REPO"/LICENSE "$R/repo/"
}
check() { "$R/repo/tests/check-spec.sh"; }

@test "README: states the status, names the license, and does not point to the specification" {
	grep -qx 'Status: under development' "$REPO/README.md"
	grep -q '^## License' "$REPO/README.md"
	grep -q 'MIT License' "$REPO/README.md"
	grep -q '(LICENSE)' "$REPO/README.md"
	refute grep -qi 'tech\.md' "$REPO/README.md"
	refute grep -qi 'implemented so far' "$REPO/README.md"
	refute grep -qi 'full specification' "$REPO/README.md"
}

@test "license: the repository carries the MIT license" {
	head -1 "$REPO/LICENSE" | grep -qx 'MIT License'
	grep -q 'Copyright (c)' "$REPO/LICENSE"
}

@test "the specification is consistent with the repository (slices, tests, deviations)" {
	run "$REPO/tests/check-spec.sh"
	echo "$output"
	[ "$status" -eq 0 ]
}

@test "the specification is written in English and opens with its version and status" {
	[ "$(sed -n 1p "$REPO/tech.md")" = '# bb — a lightweight CLI blocker for BitTorrent, DHT and blocklists' ]
	grep -qE '^\*\*Version: v[0-9]+\*\*' "$REPO/tech.md"
	grep -q '^\*\*Status: under development' "$REPO/tech.md"
	refute grep -qP '[\x{0400}-\x{04FF}]' "$REPO/tech.md"          # no Cyrillic anywhere
}

@test "check-spec: a [x] criterion that cites no test is rejected" {
	mk_repo
	sed -i 's| (tests/backend.bats: manual ban: monitor passes, block drops, unban restores)||' "$R/repo/tech.md"
	run check
	[ "$status" -ne 0 ]
	[[ $output == *"S1.2 is marked [x] but cites no test"* ]]
}

@test "check-spec: a cited test that does not exist is rejected" {
	mk_repo
	sed -i 's|tests/backend.bats: allowlist beats a broader ban|tests/backend.bats: this test was never written|' "$R/repo/tech.md"
	run check
	[ "$status" -ne 0 ]
	[[ $output == *"this test was never written"* ]]
	mk_repo
	sed -i 's|tests/backend.bats: allowlist beats a broader ban|tests/nonexistent.bats: allowlist beats a broader ban|' "$R/repo/tech.md"
	run check
	[[ $output == *"nonexistent.bats, which does not exist"* ]]
}

@test "check-spec: a status table that does not match the criteria is rejected" {
	mk_repo
	sed -i 's/^| S3 | DHT nodes | done | 4\/4 |/| S3 | DHT nodes | partial | 3\/4 |/' "$R/repo/tech.md"
	run check
	[ "$status" -ne 0 ]
	[[ $output == *"status table in section 17 does not match"* ]]
}

@test "check-spec: a table row with a title that is not the slice title is rejected" {
	mk_repo
	sed -i 's/^| S3 | DHT nodes | done/| S3 | Something else | done/' "$R/repo/tech.md"
	run check
	[ "$status" -ne 0 ]
	[[ $output == *"status table in section 17 does not match"* ]]
}

@test "check-spec: criterion numbering must follow the slice and be sequential" {
	mk_repo
	sed -i 's/\*\*S1\.3\*\*/**S1.9**/' "$R/repo/tech.md"
	run check
	[ "$status" -ne 0 ]
	[[ $output == *"should be S1.3"* ]]
}

@test "check-spec: a deviation that is mentioned in the code but not registered is rejected" {
	mk_repo
	printf '# D-099 an invented deviation\n' >>"$R/repo/src/bb"
	run check
	[ "$status" -ne 0 ]
	[[ $output == *"D-099 is referenced in the repository but not in the register"* ]]
}

@test "check-spec: an active deviation needs an annotation, a citing test and an anchor in the code" {
	mk_repo
	sed -i 's/ (see D-002)//g' "$R/repo/tech.md"
	run check
	[[ $output == *"D-002 is active but the spec text never says"* ]]
	mk_repo
	sed -i '/^| D-004 |/ s/ (tests\/cli.bats:[^)]*)//; /^| D-004 |/ s/ (tests\/integrations.bats:[^)]*)//; /^| D-004 |/ s/ (tests\/install.bats:[^)]*)//; /^| D-004 |/ s/ (tests\/json.bats:[^)]*)//' "$R/repo/tech.md"
	run check
	[[ $output == *"D-004 is active but cites no test"* ]]
	mk_repo
	sed -i 's/D-003//g' "$R/repo/src/bb"
	run check
	[[ $output == *"D-003 is not anchored anywhere"* ]]
}

@test "check-spec: deviation IDs are sequential and name sections that exist" {
	mk_repo
	sed -i 's/^| D-006 |/| D-008 |/' "$R/repo/tech.md"
	run check
	[[ $output == *"deviation IDs must be sequential"* ]]
	mk_repo
	sed -i '/^| D-001 |/ s/§6.1, §8/§6.1, §99/' "$R/repo/tech.md"
	run check
	[[ $output == *"names section 99, which does not exist"* ]]
}

@test "check-spec: a resolved deviation needs no annotation, test or anchor, but its ID stays reserved" {
	mk_repo
	sed -i '/^| D-005 |/ s/| active |/| resolved |/' "$R/repo/tech.md"
	sed -i 's/D-005//g' "$R/repo/src/bb"
	sed -i 's/ (see D-005)//g' "$R/repo/tech.md"
	run check
	echo "$output"
	[ "$status" -eq 0 ]
}

@test "CHANGELOG.md follows Keep a Changelog" {
	run bash "$REPO/tests/check-release.sh"
	echo "$output"; [ "$status" -eq 0 ]
	cp "$REPO/CHANGELOG.md" "$R/cl.md"
	sed -i 's/^## \[Unreleased\]/## Unreleased/' "$R/cl.md"
	BB_CHANGELOG=$R/cl.md run bash "$REPO/tests/check-release.sh"
	[ "$status" -ne 0 ]; [[ $output == *"Unreleased"* ]]
	cp "$REPO/CHANGELOG.md" "$R/cl.md"
	printf '\n## [0.0.1] - 2026-01-01\n\n### Tweaked\n\n- x\n' >>"$R/cl.md"
	BB_CHANGELOG=$R/cl.md run bash "$REPO/tests/check-release.sh"
	[ "$status" -ne 0 ]; [[ $output == *"unknown kind of change"* ]]
	printf '## [Unreleased]\n' >"$R/cl.md"
	BB_CHANGELOG=$R/cl.md run bash "$REPO/tests/check-release.sh"
	[ "$status" -ne 0 ]
}

@test "release check: the tag, BB_VERSION and the CHANGELOG must agree, and make dist builds checksums" {
	cp "$REPO/CHANGELOG.md" "$R/cl.md"; cp "$REPO/src/bb" "$R/bb.src"
	sed -i 's/^BB_VERSION=.*/BB_VERSION="1.2.3"/' "$R/bb.src"
	export BB_CHANGELOG=$R/cl.md BB_SOURCE=$R/bb.src
	run bash "$REPO/tests/check-release.sh" v1.2.3                 # no dated section yet
	[ "$status" -ne 0 ]; [[ $output == *"no dated section"* ]]
	sed -i 's/^## \[Unreleased\]/&\n\n## [1.2.3] - 2026-12-01/' "$R/cl.md"
	run bash "$REPO/tests/check-release.sh" v1.2.3; [ "$status" -eq 0 ]
	run bash "$REPO/tests/check-release.sh" v1.2.4; [ "$status" -ne 0 ]; [[ $output == *"does not match"* ]]
	run bash "$REPO/tests/check-release.sh" 1.2.3; [ "$status" -ne 0 ]
	unset BB_CHANGELOG BB_SOURCE
	# the real tree is a development version, so a tag for it is refused
	run bash "$REPO/tests/check-release.sh" v0.1.0; [ "$status" -ne 0 ]
	# archive and checksums (built from a copy, with the version of the copy)
	mkdir "$R/tree"; cp -r "$REPO"/src "$REPO"/lang "$REPO"/tests "$REPO"/LICENSE "$REPO"/README.md "$REPO"/Makefile "$R/tree/"
	cp "$R/cl.md" "$R/tree/CHANGELOG.md"; cp "$R/bb.src" "$R/tree/src/bb"
	cd "$R/tree"
	run make dist TAG=v1.2.3; echo "$output"; [ "$status" -eq 0 ]
	(cd dist && sha256sum -c SHA256SUMS)
	tar -tzf dist/bb-1.2.3.tar.gz | grep -q 'bb-1.2.3/src/bb'
}
