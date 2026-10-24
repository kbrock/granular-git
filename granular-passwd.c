#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <readpassphrase.h>
#include "granular.h"

int main(int argc, char **argv)
{
	char service[256];
	char user[256];
	char token[512];
	char expect[800];
	int rc;
	int verbose = 0;

	if (argc > 1 && !strcmp(argv[1], "-v")) {
		verbose = 1;
		argc--;
		argv++;
	}
	if (argc != 3) {
		fprintf(stderr, "usage: granular-passwd [-v] <profile> <host>\n");
		return 2;
	}
	if (strcmp(argv[2], "github.com")) {
		fprintf(stderr, "granular-passwd: unknown host %s\n", argv[2]);
		return 1;
	}
	if (granular_is_claude(getpid(), verbose) != 0) {
		fprintf(stderr, "granular-passwd: refusing to run under Claude or an unknown caller\n");
		return 1;
	}
	fputs("Username: ", stderr);
	user[0] = '\0';
	if (!fgets(user, sizeof(user), stdin))
		user[0] = '\0';
	user[strcspn(user, "\n")] = '\0';
	if (!*user || strchr(user, ' ')) {
		fprintf(stderr, "granular-passwd: username must be non-empty with no spaces\n");
		return 1;
	}
	if (!readpassphrase("Token: ", token, sizeof(token), RPP_REQUIRE_TTY) || !*token) {
		fprintf(stderr, "granular-passwd: no token read\n");
		return 1;
	}

	snprintf(service, sizeof(service), GRANULAR_PREFIX "%s:%s", argv[1], argv[2]);
	snprintf(expect, sizeof(expect), "%s %s", user, token);
	rc = granular_kc_set(service, user, token);
	if (rc) {
		fprintf(stderr, "granular-passwd: keychain write failed\n");
	} else if (strcmp(granular_kc_login(service, user), expect)) {
		fprintf(stderr, "granular-passwd: stored value did not read back\n");
		rc = -1;
	} else if (verbose) {
		fprintf(stderr, "granular-passwd: stored and verified %zu bytes for %s / %s\n",
			strlen(token), service, user);
	}
	memset_s(token, sizeof(token), 0, sizeof(token));
	memset_s(expect, sizeof(expect), 0, sizeof(expect));
	return rc ? 1 : 0;
}
