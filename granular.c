#include <stdio.h>
#include <crt_externs.h>
#include <errno.h>
#include <limits.h>
#include <poll.h>
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

const char *granular_pid_start(int pid)
{
	static char buf[40];
	struct kinfo_proc kp;
	size_t size = sizeof(kp);
	int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, pid };

	buf[0] = '\0';
	if (!sysctl(mib, 4, &kp, &size, NULL, 0) && size > 0)
		snprintf(buf, sizeof(buf), "%ld.%06d", (long)kp.kp_proc.p_starttime.tv_sec,
			 (int)kp.kp_proc.p_starttime.tv_usec);
	return buf;
}

const char *granular_pid_cwd(int pid)
{
	static char buf[PATH_MAX];
	struct proc_vnodepathinfo vpi;

	buf[0] = '\0';
	if (proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vpi, sizeof(vpi)) == (int)sizeof(vpi))
		snprintf(buf, sizeof(buf), "%s", vpi.pvi_cdir.vip_path);
	return buf;
}

const char *granular_claude_pids(void)
{
	static char buf[256];
	int mib[3] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL };
	size_t size = 0, used = 0;
	struct kinfo_proc *procs;

	buf[0] = '\0';
	if (sysctl(mib, 3, NULL, &size, NULL, 0))
		return buf;
	size += size / 8;
	procs = malloc(size);
	if (!procs)
		return buf;
	if (!sysctl(mib, 3, procs, &size, NULL, 0)) {
		for (size_t i = 0; i < size / sizeof(*procs); i++) {
			int pid = procs[i].kp_proc.p_pid;
			char path[PROC_PIDPATHINFO_MAXSIZE];
			char num[16];

			if (proc_pidpath(pid, path, sizeof(path)) <= 0 || !is_claude_path(path))
				continue;
			snprintf(num, sizeof(num), "%d ", pid);
			if (used + strlen(num) < sizeof(buf)) {
				strcpy(buf + used, num);
				used += strlen(num);
			}
		}
	}
	free(procs);
	return buf;
}

const char *granular_pid_path(int pid)
{
	static char buf[PROC_PIDPATHINFO_MAXSIZE];

	if (proc_pidpath(pid, buf, sizeof(buf)) <= 0)
		buf[0] = '\0';
	return buf;
}

static void copy_team(CFDictionaryRef info, char *buf, int len)
{
	CFStringRef team = CFDictionaryGetValue(info, kSecCodeInfoTeamIdentifier);

	if (team)
		CFStringGetCString(team, buf, len, kCFStringEncodingUTF8);
}

/* The running process first, which sees a binary that was replaced on disk. Its file when the
 * process cannot be inspected. */
const char *granular_pid_team(int pid)
{
	static char buf[32];
	char path[PROC_PIDPATHINFO_MAXSIZE];
	CFMutableDictionaryRef attrs = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
					 &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFNumberRef num = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &pid);
	SecCodeRef code = NULL;
	SecStaticCodeRef file = NULL;
	CFDictionaryRef info = NULL;

	buf[0] = '\0';
	CFDictionarySetValue(attrs, kSecGuestAttributePid, num);
	if (SecCodeCopyGuestWithAttributes(NULL, attrs, kSecCSDefaultFlags, &code) == errSecSuccess &&
	    SecCodeCopySigningInformation(code, kSecCSSigningInformation, &info) == errSecSuccess)
		copy_team(info, buf, sizeof(buf));
	else if (proc_pidpath(pid, path, sizeof(path)) > 0) {
		CFURLRef url = CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault, (UInt8 *)path,
								       strlen(path), false);

		if (SecStaticCodeCreateWithPath(url, kSecCSDefaultFlags, &file) == errSecSuccess &&
		    SecCodeCopySigningInformation(file, kSecCSSigningInformation, &info) == errSecSuccess)
			copy_team(info, buf, sizeof(buf));
		CFRelease(url);
	}
	if (info)
		CFRelease(info);
	if (file)
		CFRelease(file);
	if (code)
		CFRelease(code);
	CFRelease(num);
	CFRelease(attrs);
	return buf;
}

/* The keychain file that holds the logins. */
static SecKeychainRef vault;

int granular_vault(const char *path)
{
	SecKeychainStatus status;

	if (vault) {
		CFRelease(vault);
		vault = NULL;
	}
	if (SecKeychainOpen(path, &vault) != errSecSuccess || SecKeychainGetStatus(vault, &status) != errSecSuccess) {
		if (vault)
			CFRelease(vault);
		vault = NULL;
		return -1;
	}
	return 0;
}

/* Asks for the new password in a system dialog, so it never passes through this program. The vault
 * stays unlocked for a day and through sleep. */
int granular_vault_create(const char *path)
{
	SecKeychainRef kc = NULL;
	SecKeychainSettings settings = { SEC_KEYCHAIN_SETTINGS_VERS1, 0, 1, 86400 };

	if (SecKeychainCreate(path, 0, NULL, true, NULL, &kc) != errSecSuccess)
		return -1;
	SecKeychainSetSettings(kc, &settings);
	CFRelease(kc);
	return 0;
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
	if (vault) {
		CFArrayRef list = CFArrayCreate(kCFAllocatorDefault, (const void **)&vault, 1, &kCFTypeArrayCallBacks);

		CFDictionarySetValue(q, kSecMatchSearchList, list);
		CFRelease(list);
	}
	return q;
}

int granular_kc_set(const char *service, const char *account, const char *secret, const char *description)
{
	CFMutableDictionaryRef q = item_query(service, account);
	CFMutableDictionaryRef attrs = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, q);
	CFDataRef data = CFDataCreate(kCFAllocatorDefault, (const UInt8 *)secret, strlen(secret));
	CFStringRef desc = CFStringCreateWithCString(kCFAllocatorDefault, description, kCFStringEncodingUTF8);
	OSStatus st;

	CFDictionarySetValue(attrs, kSecValueData, data);
	CFDictionarySetValue(attrs, kSecAttrDescription, desc);
	if (vault) {
		CFDictionaryRemoveValue(attrs, kSecMatchSearchList);
		CFDictionarySetValue(attrs, kSecUseKeychain, vault);
	}
	SecItemDelete(q);
	st = SecItemAdd(attrs, NULL);
	CFRelease(desc);
	CFRelease(data);
	CFRelease(attrs);
	CFRelease(q);
	return st == errSecSuccess ? 0 : -1;
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
		CFStringRef desc = CFDictionaryGetValue(item, kSecAttrDescription);
		char user[256];
		char note[256];

		if (acct && data &&
		    CFStringGetCString(acct, user, sizeof(user), kCFStringEncodingUTF8) &&
		    *user && !strchr(user, ' ') &&
		    strlen(user) + 1 + CFDataGetLength(data) < sizeof(buf)) {
			size_t n = strlen(user);

			memcpy(buf, user, n);
			buf[n] = ' ';
			memcpy(buf + n + 1, CFDataGetBytePtr(data), CFDataGetLength(data));
			buf[n + 1 + CFDataGetLength(data)] = '\0';
			if (desc && CFStringGetCString(desc, note, sizeof(note), kCFStringEncodingUTF8) && *note &&
			    strlen(buf) + 1 + strlen(note) < sizeof(buf)) {
				strcat(buf, " ");
				strcat(buf, note);
			}
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

/* The socket is trusted only if it is ours and the directory holding it is ours and closed to others. */
int granular_fetch_socket(const char *path)
{
	struct sockaddr_un addr;
	struct stat st;
	char dir[PATH_MAX];
	char *slash;
	int fd;

	if (lstat(path, &st))
		return -1;
	if (!S_ISSOCK(st.st_mode) || st.st_uid != getuid())
		return -2;
	snprintf(dir, sizeof(dir), "%s", path);
	slash = strrchr(dir, '/');
	if (!slash)
		return -2;
	*slash = '\0';
	if (lstat(dir, &st) || !S_ISDIR(st.st_mode) || st.st_uid != getuid() || (st.st_mode & 077))
		return -2;
	if (sock_addr(&addr, path))
		return -2;
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

static char enter_line[64];

const char *granular_last_line(void)
{
	return enter_line;
}

int granular_accept_or_enter(int listen_fd)
{
	static int stdin_open = 1;
	struct pollfd fds[2] = { { listen_fd, POLLIN, 0 }, { STDIN_FILENO, POLLIN, 0 } };

	if (poll(fds, stdin_open ? 2 : 1, -1) < 0)
		return -1;
	if (stdin_open && (fds[1].revents & (POLLIN | POLLHUP))) {
		size_t len = 0;
		char c;
		ssize_t n;

		while ((n = read(STDIN_FILENO, &c, 1)) == 1 && c != '\n')
			if (len < sizeof(enter_line) - 1)
				enter_line[len++] = c;
		enter_line[len] = '\0';
		if (n <= 0)
			stdin_open = 0;
		return -2;
	}
	return granular_accept(listen_fd);
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

int granular_exec(const char *path, const char *env_name, const char *value)
{
	char **argv = *_NSGetArgv();

	if (access(path, X_OK))
		return -1;
	if (*value)
		setenv(env_name, value, 1);
	else
		unsetenv(env_name);
	argv[0] = "gh";
	execv(path, argv);
	return -1;
}
