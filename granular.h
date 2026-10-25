#ifndef GRANULAR_H
#define GRANULAR_H

/* Keychain service name is GRANULAR_PREFIX + profile + ":" + host, e.g. "granular:ro:github.com".
 * Account is the username and the secret is the token. The profile is "ro" or "rw". */
#define GRANULAR_PREFIX "granular:"

/* Parent of pid, or -1 on error. */
int granular_parent_pid(int pid);

/* Start time of pid as "seconds.microseconds" from a static buffer, or "" if there is no such
 * process. A reused pid has a different start time. */
const char *granular_pid_start(int pid);

/* Executable path of pid from a static buffer, or "" if unreadable. */
const char *granular_pid_path(int pid);

/* 1 if the claude-code executable is an ancestor of pid, 0 if not, -1 on error.
 * A nonzero verbose prints the walk to stderr. */
int granular_is_claude(int pid, int verbose);

/* Hard-coded for 1A: "rw" only when is_claude is 0; Claude or an error gets "ro". */
const char *granular_account(int is_claude);

/* Copies the stored secret into buf (NUL-terminated). Returns its length,
 * or -1 if the item is missing or the read fails. */
int granular_kc_get(const char *service, const char *account, char *buf, int len);

/* granular_kc_get for callers that cannot pass a buffer (Spinel). Returns the
 * secret from a static buffer, or "" if the item is missing. */
const char *granular_kc_token(const char *service, const char *account);

/* The first item of service, narrowed to account if account is not empty, as "<account> <secret>"
 * from a static buffer, or "" if there is none or the account holds a space. */
const char *granular_kc_login(const char *service, const char *account);

/* Reads a line from the tty with no echo into a static buffer, or "" if there
 * is no tty or nothing was read. */
const char *granular_read_secret(const char *prompt);

/* Creates path as a 0700 directory owned by the caller. Returns 0 on success; -1 if it
 * exists as anything else (a symlink, a file, another user's directory). */
int granular_private_dir(const char *path);

/* Unix socket primitives for the daemon and its clients. Return an fd, or -1 on error. */
int granular_listen(const char *path);   /* removes a stale socket, mode 0600 */
int granular_connect(const char *path);
int granular_accept(int listen_fd);
int granular_close(int fd);

/* granular_accept, or -2 after a line was read from stdin. Once stdin reaches EOF it is no longer
 * watched. */
int granular_accept_or_enter(int listen_fd);

/* The line that granular_accept_or_enter last read from stdin, without its newline. */
const char *granular_last_line(void);

/* Pids of all running claude executables, separated by spaces, from a static buffer. */
const char *granular_claude_pids(void);

/* Working directory of pid from a static buffer, or "" if unreadable. */
const char *granular_pid_cwd(int pid);

/* Runs the next executable called name on PATH that is not a copy of this program, with env_name set to
 * value (an empty value removes it) and this program's original arguments. Returns -1 if none
 * could be run. */
int granular_exec_other(const char *name, const char *env_name, const char *value);

/* Pid of the process on the other end of a connected socket, or -1. */
int granular_peer_pid(int fd);

/* One newline-terminated line (newline stripped) from a static buffer, "" on EOF or error. */
const char *granular_read_line(int fd);
int granular_write_line(int fd, const char *s);   /* 0 on success */

/* Creates or updates the item. Returns 0 on success. */
int granular_kc_set(const char *service, const char *account, const char *secret);

#endif
