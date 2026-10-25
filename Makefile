CFLAGS  = -Wall -Wextra
LDFLAGS = -framework Security -framework CoreFoundation
PROGS   = granular-git granular-passwd

all: $(PROGS)

$(PROGS): %: %.c granular.c granular.h
	$(CC) $(CFLAGS) $< granular.c $(LDFLAGS) -o $@

BUILD = build

link: $(BUILD)/granular
	ln -sf granular $(BUILD)/granular-git
	ln -sf granular $(BUILD)/granular-passwd
	ln -sf granular $(BUILD)/granular-daemon
	mkdir -p $(BUILD)/shims
	ln -sf ../granular $(BUILD)/shims/gh

$(BUILD)/granular.o: granular.c granular.h
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -c granular.c -o $@

$(BUILD)/granular: granular.rb $(BUILD)/granular.o
	spinel granular.rb -o $@ --link $(BUILD)/granular.o --link -Wl,-framework,Security --link -Wl,-framework,CoreFoundation

PREFIX = /usr/local/bin

install: link
	install -m 755 $(BUILD)/granular $(PREFIX)/granular
	for n in granular-git granular-passwd granular-daemon gh; do ln -sf granular $(PREFIX)/$$n; done

uninstall:
	for n in granular-git granular-passwd granular-daemon gh; do \
		[ "$$(readlink $(PREFIX)/$$n)" = granular ] && rm $(PREFIX)/$$n; done; \
		rm -f $(PREFIX)/granular

clean:
	rm -rf $(PROGS) $(BUILD)

.PHONY: all link install uninstall clean
