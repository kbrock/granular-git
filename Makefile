CFLAGS = -Wall -Wextra -Wno-deprecated-declarations
BUILD  = build

all: link

link: $(BUILD)/granular
	ln -sf granular $(BUILD)/granular-git
	ln -sf granular $(BUILD)/granular-passwd
	ln -sf granular $(BUILD)/granular-daemon

$(BUILD)/granular.o: granular.c granular.h
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -c granular.c -o $@

SIGN_ID = granular-signing

$(BUILD)/granular: granular.rb $(BUILD)/granular.o
	./sign-identity.sh $(SIGN_ID)
	spinel granular.rb -o $@ --link $(BUILD)/granular.o --link -Wl,-framework,Security --link -Wl,-framework,CoreFoundation
	codesign --force -s $(SIGN_ID) $@

PREFIX = /usr/local/bin

install: link
	install -m 755 $(BUILD)/granular $(PREFIX)/granular
	for n in granular-git granular-passwd granular-daemon gh; do ln -sf granular $(PREFIX)/$$n; done

uninstall:
	for n in granular-git granular-passwd granular-daemon gh; do \
		[ "$$(readlink $(PREFIX)/$$n)" = granular ] && rm $(PREFIX)/$$n; done; \
		rm -f $(PREFIX)/granular

clean:
	rm -rf $(BUILD)

.PHONY: all link install uninstall clean
