CFLAGS = -Wall -Wextra -Wno-deprecated-declarations
BUILD  = build
DIST   = dist
PREFIX = /usr/local/bin

LINKS   = granular-git granular-passwd granular-daemon granular-trust gh
SCRIPTS = granular-audit granular-test
NAMES   = granular $(LINKS) $(SCRIPTS)
SOURCES = granular.rb $(wildcard lib/granular/*.rb)
# v0.2.0 at that tag, v0.2.0+29 when 29 commits past it.
NAME := $(shell git describe --tags --always | sed 's/-\([0-9]*\)-g.*/+\1/')
TARBALL = $(DIST)/granular-$(NAME).tgz

all: $(BUILD)/granular

$(BUILD)/granular.o: granular.c granular.h
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -c granular.c -o $@

# Lint, compile, sign, test. A step that fails deletes the binary, so the next make starts over.
$(BUILD)/granular: $(SOURCES) $(BUILD)/granular.o
	bundle exec rubocop
	spinel granular.rb -o $@ --link $(BUILD)/granular.o --link -Wl,-framework,Security --link -Wl,-framework,CoreFoundation
	@bin/sign $@
	bin/ci $@

# The links are real files in build, so install and dist take the same list.
$(LINKS:%=$(BUILD)/%): $(BUILD)/granular
	ln -sf granular $@

install: $(BUILD)/granular $(LINKS:%=$(BUILD)/%)
	cd $(BUILD) && cp -Rf granular $(LINKS) $(PREFIX)
	cp $(SCRIPTS) $(PREFIX)
	$(PREFIX)/granular-audit

uninstall:
	rm -f $(NAMES:%=$(PREFIX)/%)

dist: $(TARBALL)

$(TARBALL): $(BUILD)/granular $(LINKS:%=$(BUILD)/%) $(SCRIPTS)
	@git diff --quiet HEAD || echo "warning: uncommitted changes are in this tarball" >&2
	@mkdir -p $(DIST)
	tar czf $@ -C $(BUILD) granular $(LINKS) -C .. $(SCRIPTS)
	cd $(DIST) && shasum -a 256 $(notdir $@) | tee $(notdir $@).sha256
	@echo

release: dist
	bin/release

clean:
	rm -rf $(BUILD) $(DIST)

.PHONY: all install uninstall dist release clean
.DELETE_ON_ERROR:
