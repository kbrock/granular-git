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
	rm -rf $(BUILD)/dist $(BUILD)/granular-*.tgz
	mkdir -p $(BUILD)/dist
	$(MAKE) install PREFIX=$(BUILD)/dist
	cd $(BUILD)/dist && tar czf ../granular-$(VERSION).tgz *

clean:
	rm -rf $(BUILD)

.PHONY: all link install uninstall dist clean
