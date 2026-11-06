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

install: $(PREFIX)/granular $(addprefix $(PREFIX)/,$(LINKS) gh)

uninstall:
	for n in granular-git granular-passwd granular-daemon gh; do \
		[ "$$(readlink $(PREFIX)/$$n)" = granular ] && rm $(PREFIX)/$$n; done; \
		rm -f $(PREFIX)/granular

clean:
	rm -rf $(BUILD)

.PHONY: all link install uninstall clean
