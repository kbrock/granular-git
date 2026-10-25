#include <stdio.h>
#include <crt_externs.h>
#include <errno.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <libproc.h>
#include <readpassphrase.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/un.h>
#include <sys/sysctl.h>
#include <Security/Security.h>
#include "granular.h"

#define MAX_DEPTH 64

#define vlog(v, ...) do { if (v) fprintf(stderr, __VA_ARGS__); } while (0)

static int is_claude_path(const char *path)
{
	const char *base = strrchr(path, '/');

	return base && !strcmp(base + 1, "claude");
}

/* proc_pidinfo is refused for root-owned processes such as login; sysctl is not. */
int granular_parent_pid(int pid)
{
	struct kinfo_proc kp;
	size_t size = sizeof(kp);
	int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, pid };

	if (sysctl(mib, 4, &kp, &size, NULL, 0) || size == 0)
		return -1;
	return kp.kp_eproc.e_ppid;
}

const char *granular_pid_path(int pid)
{
	static char buf[PROC_PIDPATHINFO_MAXSIZE];

	if (proc_pidpath(pid, buf, sizeof(buf)) <= 0)
		buf[0] = '\0';
	return buf;
}

int granular_is_claude(int pid, int verbose)
{
	for (int depth = 0; pid > 1 && depth < MAX_DEPTH; depth++) {
		char path[PROC_PIDPATHINFO_MAXSIZE];
		int have_path = proc_pidpath(pid, path, sizeof(path)) > 0;

		vlog(verbose, "walk pid=%d path=%s\n", pid, have_path ? path : "(none)");
		if (have_path && is_claude_path(path))
			return 1;
		pid = granular_parent_pid(pid);
		if (pid < 0) {
			vlog(verbose, "walk parent lookup failed\n");
			return -1;
		}
	}
	if (pid != 1)
		vlog(verbose, "walk ended at pid=%d\n", pid);
	return pid == 1 ? 0 : -1;
}

const char *granular_account(int is_claude)
{
	return is_claude == 0 ? "rw" : "ro";
}

static CFMutableDictionaryRef new_dictionary(void)
{
	return CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
					 &kCFTypeDictionaryKeyCallBacks,
					 &kCFTypeDictionaryValueCallBacks);
}

static CFMutableDictionaryRef item_query(const char *service, const char *account)
{
	CFMutableDictionaryRef q = new_dictionary();
	CFStringRef s = CFStringCreateWithCString(kCFAllocatorDefault, service, kCFStringEncodingUTF8);

	CFDictionarySetValue(q, kSecClass, kSecClassGenericPassword);
	CFDictionarySetValue(q, kSecAttrService, s);
	CFRelease(s);
	if (account && *account) {
		CFStringRef a = CFStringCreateWithCString(kCFAllocatorDefault, account, kCFStringEncodingUTF8);

		CFDictionarySetValue(q, kSecAttrAccount, a);
		CFRelease(a);
	}
	return q;
}

int granular_kc_get(const char *service, const char *account, char *buf, int len)
{
	CFMutableDictionaryRef q = item_query(service, account);
	CFDataRef data = NULL;
	int n = -1;

	CFDictionarySetValue(q, kSecReturnData, kCFBooleanTrue);
	CFDictionarySetValue(q, kSecMatchLimit, kSecMatchLimitOne);
	if (SecItemCopyMatching(q, (CFTypeRef *)&data) == errSecSuccess) {
		CFIndex dlen = CFDataGetLength(data);

		if (dlen < len) {
			memcpy(buf, CFDataGetBytePtr(data), dlen);
			buf[dlen] = '\0';
			n = (int)dlen;
		}
		CFRelease(data);
	}
	CFRelease(q);
	return n;
}

int granular_kc_set(const char *service, const char *account, const char *secret)
{
	CFMutableDictionaryRef q = item_query(service, account);
	CFMutableDictionaryRef attrs = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, q);
	CFDataRef data = CFDataCreate(kCFAllocatorDefault, (const UInt8 *)secret, strlen(secret));
	OSStatus st;

	CFDictionarySetValue(attrs, kSecValueData, data);
	st = SecItemAdd(attrs, NULL);
	if (st == errSecDuplicateItem) {
		CFMutableDictionaryRef change = new_dictionary();

		CFDictionarySetValue(change, kSecValueData, data);
		st = SecItemUpdate(q, change);
		CFRelease(change);
	}
	CFRelease(data);
	CFRelease(attrs);
	CFRelease(q);
	return st == errSecSuccess ? 0 : -1;
}

const char *granular_kc_token(const char *service, const char *account)
{
	static char buf[512];

	if (granular_kc_get(service, account, buf, sizeof(buf)) < 0)
		buf[0] = '\0';
	return buf;
}

const char *granular_kc_login(const char *service, const char *account)
{
	static char buf[512];
	CFMutableDictionaryRef q = item_query(service, account);
	CFDictionaryRef item = NULL;

	buf[0] = '\0';
	CFDictionarySetValue(q, kSecReturnAttributes, kCFBooleanTrue);
	CFDictionarySetValue(q, kSecReturnData, kCFBooleanTrue);
	CFDictionarySetValue(q, kSecMatchLimit, kSecMatchLimitOne);
	if (SecItemCopyMatching(q, (CFTypeRef *)&item) == errSecSuccess) {
		CFStringRef acct = CFDictionaryGetValue(item, kSecAttrAccount);
		CFDataRef data = CFDictionaryGetValue(item, kSecValueData);
		char user[256];

		if (acct && data &&
		    CFStringGetCString(acct, user, sizeof(user), kCFStringEncodingUTF8) &&
		    *user && !strchr(user, ' ') &&
		    strlen(user) + 1 + CFDataGetLength(data) < sizeof(buf)) {
			size_t n = strlen(user);

			memcpy(buf, user, n);
			buf[n] = ' ';
			memcpy(buf + n + 1, CFDataGetBytePtr(data), CFDataGetLength(data));
			buf[n + 1 + CFDataGetLength(data)] = '\0';
		}
		CFRelease(item);
	}
	CFRelease(q);
	return buf;
}

const char *granular_read_secret(const char *prompt)
{
	static char buf[512];

	if (!readpassphrase(prompt, buf, sizeof(buf), RPP_REQUIRE_TTY))
		buf[0] = '\0';
	return buf;
}

static int sock_addr(struct sockaddr_un *addr, const char *path)
{
	if (strlen(path) >= sizeof(addr->sun_path))
		return -1;
	memset(addr, 0, sizeof(*addr));
	addr->sun_family = AF_UNIX;
	strcpy(addr->sun_path, path);
	return 0;
}

int granular_private_dir(const char *path)
{
	struct stat st;

	if (mkdir(path, 0700) && errno != EEXIST)
		return -1;
	if (lstat(path, &st) || !S_ISDIR(st.st_mode) || st.st_uid != getuid())
		return -1;
	return chmod(path, 0700);
}

/* A silent peer must not block a single-threaded daemon, and a vanished one must not kill it.
 * The daemon reads requests with a short timeout; a client waits long enough for the daemon
 * to sit in a Keychain dialog. */
static void sock_opts(int fd, int timeout_secs)
{
	struct timeval tv = { timeout_secs, 0 };
	int on = 1;

	setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
	setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof(on));
}

int granular_listen(const char *path)
{
	struct sockaddr_un addr;
	int fd;

	if (sock_addr(&addr, path))
		return -1;
	fd = socket(AF_UNIX, SOCK_STREAM, 0);
	if (fd < 0)
		return -1;
	unlink(path);
	if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) || chmod(path, 0600) || listen(fd, 8)) {
		close(fd);
		return -1;
	}
	return fd;
}

int granular_connect(const char *path)
{
	struct sockaddr_un addr;
	int fd;

	if (sock_addr(&addr, path))
		return -1;
	fd = socket(AF_UNIX, SOCK_STREAM, 0);
	if (fd < 0)
		return -1;
	if (connect(fd, (struct sockaddr *)&addr, sizeof(addr))) {
		close(fd);
		return -1;
	}
	sock_opts(fd, 60);
	return fd;
}

int granular_accept(int listen_fd)
{
	int fd = accept(listen_fd, NULL, NULL);

	if (fd >= 0)
		sock_opts(fd, 2);
	return fd;
}

int granular_peer_pid(int fd)
{
	pid_t pid;
	socklen_t len = sizeof(pid);

	if (getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &len))
		return -1;
	return pid;
}

const char *granular_read_line(int fd)
{
	static char buf[1024];
	size_t n = 0;
	char c;

	while (n < sizeof(buf) - 1 && read(fd, &c, 1) == 1 && c != '\n')
		buf[n++] = c;
	buf[n] = '\0';
	return buf;
}

int granular_write_line(int fd, const char *s)
{
	size_t len = strlen(s);

	if (write(fd, s, len) != (ssize_t)len || write(fd, "\n", 1) != 1)
		return -1;
	return 0;
}

int granular_close(int fd)
{
	return close(fd);
}

int granular_exec_other(const char *name, const char *env_name, const char *value)
{
	char self[PROC_PIDPATHINFO_MAXSIZE];
	char real_self[PATH_MAX];
	char real_cand[PATH_MAX];
	char cand[PATH_MAX];
	char **argv = *_NSGetArgv();
	char *path = getenv("PATH");
	char *dup;
	char *dir;
	char *save = NULL;
	const char *self_name;

	if (!path || proc_pidpath(getpid(), self, sizeof(self)) <= 0 || !realpath(self, real_self))
		return -1;
	self_name = strrchr(real_self, '/');
	dup = strdup(path);
	for (dir = strtok_r(dup, ":", &save); dir; dir = strtok_r(NULL, ":", &save)) {
		snprintf(cand, sizeof(cand), "%s/%s", dir, name);
		/* Another copy of this program (build/ and an install) would exec back and forth. */
		if (access(cand, X_OK) || !realpath(cand, real_cand) ||
		    !strcmp(strrchr(real_cand, '/'), self_name))
			continue;
		if (*value)
			setenv(env_name, value, 1);
		else
			unsetenv(env_name);
		argv[0] = (char *)name;
		execv(cand, argv);
	}
	free(dup);
	return -1;
}
