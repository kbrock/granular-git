CFLAGS = -Wall -Wextra -Wno-deprecated-declarations
BUILD  = build

all: link

LINKS = granular-git granular-passwd granular-daemon

# link(target, source): the target is a symlink to the source's file name. It is made once, when the
# target is missing, and after the source exists.
define link
$(1): | $(2)
	ln -s $(notdir $(2)) $(1)
endef

$(foreach n,$(LINKS),$(eval $(call link,$(BUILD)/$(n),$(BUILD)/granular)))

link: $(BUILD)/granular $(addprefix $(BUILD)/,$(LINKS))

$(BUILD)/granular.o: granular.c granular.h
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -c granular.c -o $@

SIGN_ID = granular-signing

$(BUILD)/granular: granular.rb $(BUILD)/granular.o
	./sign-identity.sh $(SIGN_ID)
	spinel granular.rb -o $@ --link $(BUILD)/granular.o --link -Wl,-framework,Security --link -Wl,-framework,CoreFoundation
	codesign --force -s $(SIGN_ID) $@

PREFIX = /usr/local/bin

$(PREFIX)/granular: $(BUILD)/granular
	install -m 755 $< $@

$(foreach n,$(LINKS) gh,$(eval $(call link,$(PREFIX)/$(n),$(PREFIX)/granular)))

SCRIPTS = granular-audit granular-test-ro granular-test-rw

$(addprefix $(PREFIX)/,$(SCRIPTS)): $(PREFIX)/%: %
	install -m 755 $< $@

install: $(PREFIX)/granular $(addprefix $(PREFIX)/,$(LINKS) gh $(SCRIPTS))

uninstall:
	for n in granular-git granular-passwd granular-daemon gh; do \
		[ "$$(readlink $(PREFIX)/$$n)" = granular ] && rm $(PREFIX)/$$n; done; \
		rm -f $(PREFIX)/granular
	rm -f $(addprefix $(PREFIX)/,$(SCRIPTS))

VERSION := $(shell sed -n 's/^VERSION = "\(.*\)"/\1/p' granular.rb)

# A tarball of what install puts in PREFIX, links included: sudo tar xzf granular-<version>.tgz -C /usr/local/bin
dist: $(BUILD)/granular
	rm -rf $(BUILD)/dist $(BUILD)/granular-*.tgz $(BUILD)/granular-*.sha256
	mkdir -p $(BUILD)/dist
	$(MAKE) install PREFIX=$(BUILD)/dist
	cd $(BUILD)/dist && tar czf ../granular-$(VERSION).tgz *
	cd $(BUILD) && shasum -a 256 granular-$(VERSION).tgz | tee granular-$(VERSION).tgz.sha256

# Publishes a GitHub release for VERSION: builds the tarball and checksum, then gh creates the tag
# v$(VERSION) on REMOTE and attaches both, with the notes from CHANGELOG.md. REMOTE is the remote main
# tracks, else origin: make release REMOTE=upstream. Run it from your own terminal, on main, after the
# bump is merged and pulled.
REMOTE ?= $(or $(shell git config --get branch.main.remote),origin)

release: dist
	@test -z "$$(git status --porcelain --untracked-files=no)" || { echo "release: commit or stash your changes first"; exit 1; }
	@[ "$$(git rev-parse --abbrev-ref HEAD)" = main ] || { echo "release: switch to main"; exit 1; }
	@git fetch -q $(REMOTE) && [ "$$(git rev-parse HEAD)" = "$$(git rev-parse $(REMOTE)/main)" ] || { echo "release: main is not $(REMOTE)/main (git pull)"; exit 1; }
	@grep -q '^## \[$(VERSION)\]' CHANGELOG.md || { echo "release: CHANGELOG.md has no [$(VERSION)] section"; exit 1; }
	gh release create v$(VERSION) $(BUILD)/granular-$(VERSION).tgz $(BUILD)/granular-$(VERSION).tgz.sha256 \
		--title v$(VERSION) --notes "$$(sed -n '/^## \[$(VERSION)\]/,/^## \[/{/^## \[/!p;}' CHANGELOG.md)"

clean:
	rm -rf $(BUILD)

.PHONY: all link install uninstall dist release clean
