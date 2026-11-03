PREFIX ?= /usr/local
SHAREDIR ?= /usr/share/bb

.PHONY: test lint install

test:            ## full suite (needs root: runs in a private network namespace)
	tests/run.sh

lint:
	shellcheck -x -S warning src/bb
	bash tests/lint.sh

install:         ## manual install; the installer command (bb install) comes in a later step
	install -D -m 0755 src/bb $(DESTDIR)$(PREFIX)/sbin/bb
	install -D -m 0644 src/net.awk $(DESTDIR)$(SHAREDIR)/net.awk
	install -D -m 0644 lang/en.sh $(DESTDIR)$(SHAREDIR)/lang/en.sh
	install -D -m 0644 lang/ru.sh $(DESTDIR)$(SHAREDIR)/lang/ru.sh
