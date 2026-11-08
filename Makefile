PREFIX ?= /usr/local
SHAREDIR ?= /usr/share/bb

.PHONY: test lint spec install dist release-check

test:            ## full suite (needs root: runs in a private network namespace)
	tests/run.sh

spec:            ## check tech.md against the tests and the code (slices, deviation register)
	tests/check-spec.sh

lint:
	shellcheck -x -S warning src/bb
	bash tests/lint.sh

install:         ## manual install; the installer command (bb install) comes in a later step
	install -D -m 0755 src/bb $(DESTDIR)$(PREFIX)/sbin/bb
	install -D -m 0644 src/net.awk $(DESTDIR)$(SHAREDIR)/net.awk
	install -D -m 0644 lang/en.sh $(DESTDIR)$(SHAREDIR)/lang/en.sh
	install -D -m 0644 lang/ru.sh $(DESTDIR)$(SHAREDIR)/lang/ru.sh

release-check:   ## CHANGELOG format; with TAG=vX.Y.Z also that tag, version and CHANGELOG agree
	tests/check-release.sh $(TAG)

dist:            ## release archive and SHA256SUMS in dist/ (TAG=vX.Y.Z)
	tests/check-release.sh $(TAG)
	rm -rf dist && mkdir -p dist/bb-$(TAG:v%=%)
	cp -r src lang LICENSE README.md CHANGELOG.md Makefile dist/bb-$(TAG:v%=%)/
	tar -C dist -czf dist/bb-$(TAG:v%=%).tar.gz bb-$(TAG:v%=%)
	rm -rf dist/bb-$(TAG:v%=%)
	cd dist && sha256sum bb-$(TAG:v%=%).tar.gz > SHA256SUMS
