CFLAGS = -Wall -Wextra -Wno-deprecated-declarations
BUILD  = build
DIST   = dist
PREFIX = /usr/local/bin

LINKS   = granular-git granular-passwd granular-daemon granular-trust gh
SCRIPTS = granular-audit granular-test
NAMES   = granular $(LINKS) $(SCRIPTS)
SOURCES = granular.rb lib/granular.rb $(wildcard lib/granular/*.rb)
# v0.2.0 at that tag, v0.2.0+29 when 29 commits past it.
ARCH := $(shell uname -m)
NAME := $(shell git describe --tags --always | sed 's/-\([0-9]*\)-g.*/+\1/')
TARBALL = $(DIST)/granular-$(NAME)-$(ARCH).tgz

# make: lint, unit tests, dev build, stories. Runs anywhere. make build adds the signed build and smoke test.
all: $(BUILD)/dev/granular
	bin/ci $<

build: all $(BUILD)/granular

$(BUILD)/granular.o: granular.c granular.h
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -c granular.c -o $@

# Compile, sign, smoke test. A step that fails deletes the binary, so the next make starts over.
$(BUILD)/granular: $(SOURCES) $(BUILD)/granular.o
	spinel granular.rb -o $@ --link $(BUILD)/granular.o --link -Wl,-framework,Security --link -Wl,-framework,CoreFoundation
	@bin/sign $@
	bin/smoke $@

# The dev build: every command open, a vault made for each test run. It is never installed or packed.
$(BUILD)/dev/granular: $(SOURCES) $(wildcard dev/*.rb test/unit/*.rb) $(BUILD)/granular.o
	bundle exec rubocop
	bin/unit
	mkdir -p $(BUILD)/dev
	spinel dev/granular.rb -o $@ --link $(BUILD)/granular.o --link -Wl,-framework,Security --link -Wl,-framework,CoreFoundation

# The links and scripts are in build, so install and dist take the same list.
$(LINKS:%=$(BUILD)/%): $(BUILD)/granular
	ln -sf granular $@

$(SCRIPTS:%=$(BUILD)/%): $(BUILD)/%: %
	cp $< $@

# install writes a new file and renames it into place. Copying over the old binary keeps its inode, and macOS kills it (Killed: 9) on the stale signature.
install: build $(NAMES:%=$(BUILD)/%)
	cd $(BUILD) && install -m 755 granular $(SCRIPTS) $(PREFIX)
	cd $(PREFIX) && for l in $(LINKS); do ln -sf granular $$l; done
	$(PREFIX)/granular-audit

uninstall:
	rm -f $(NAMES:%=$(PREFIX)/%)

dist: $(TARBALL)

$(TARBALL): $(NAMES:%=$(BUILD)/%)
	@git diff --quiet HEAD || echo "warning: uncommitted changes are in this tarball" >&2
	@mkdir -p $(DIST)
	tar czf $@ -C $(BUILD) $(NAMES)
	@echo $@

release:
	bin/release

clean:
	rm -rf $(BUILD)

.PHONY: all build install uninstall dist release clean
.DELETE_ON_ERROR:
