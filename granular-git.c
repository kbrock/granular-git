#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include "granular.h"

#define SELF_PREFIX "granular-"

int main(int argc, char **argv)
{
	const char *self = strrchr(argv[0], '/');
	char service[256];
	char line[1024];
	char host[256] = "";
	char user[256] = "";
	const char *profile;
	const char *login;
	int verbose = 0;

	self = self ? self + 1 : argv[0];
	if (argc > 1 && !strcmp(argv[1], "-v")) {
		verbose = 1;
		argc--;
		argv++;
	}
	if (argc != 2 || strncmp(self, SELF_PREFIX, strlen(SELF_PREFIX))) {
		fprintf(stderr, "usage: granular-git [-v] <get|store|erase>\n");
		return 2;
	}

	if (!strcmp(argv[1], "store"))
		fprintf(stderr, "granular-git: store ignored\n");
	if (strcmp(argv[1], "get"))
		return 0;

	while (fgets(line, sizeof(line), stdin) && strcmp(line, "\n")) {
		if (!strncmp(line, "host=", 5)) {
			snprintf(host, sizeof(host), "%s", line + 5);
			host[strcspn(host, "\n")] = '\0';
		}
		if (!strncmp(line, "username=", 9)) {
			snprintf(user, sizeof(user), "%s", line + 9);
			user[strcspn(user, "\n")] = '\0';
		}
	}
	if (strcmp(host, "github.com"))
		return 0;

	profile = granular_account(granular_is_claude(getpid(), verbose));
	snprintf(service, sizeof(service), GRANULAR_PREFIX "%s:%s", profile, host);
	login = granular_kc_login(service, user);
	if (!*login) {
		fprintf(stderr, "granular-git: no login in %s\n", service);
		return 1;
	}
	printf("username=%.*s\npassword=%s\n", (int)strcspn(login, " "), login, strchr(login, ' ') + 1);
	return 0;
}
