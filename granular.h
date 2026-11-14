#ifndef GRANULAR_H
#define GRANULAR_H

/* Parent of pid, or -1 on error. */
int granular_parent_pid(int pid);

/* Start time of pid as "seconds.microseconds" from a static buffer, or "" if there is no such
 * process. A reused pid has a different start time. */
const char *granular_pid_start(int pid);

/* Team identifier from the code signature of the running process pid, from a static buffer, or ""
 * if it is unsigned or unreadable. */
const char *granular_pid_team(int pid);

/* Executable path of pid from a static buffer, or "" if unreadable. */
const char *granular_pid_path(int pid);
const char *granular_pid_exec(int pid);

/* Makes path the only keychain that granular_kc_login and granular_kc_set use. Returns -1 if the file
 * cannot be opened. */
int granular_vault(const char *path);

/* Creates the keychain file at path. A system dialog asks for its password. It stays unlocked for a day
 * and through sleep. Returns 0 on success. */
int granular_vault_create(const char *path);

/* The first item of service, narrowed to account if account is not empty, as "<account> <secret>" and
 * " <description>" when it has one, from a static buffer, or "" if there is none or the account holds a
 * space. */
const char *granular_kc_login(const char *service, const char *account);

/* A listing of the vault's items whose service starts with prefix. Open returns the number of items in
 * the vault (not all match). Get returns the service name of item i from a static buffer, or "" if i is
 * out of range or the name does not start with the prefix. Close frees the listing. Attributes only, so
 * no prompt. */
int granular_kc_list_open(const char *prefix);
const char *granular_kc_list_get(int i);
int granular_kc_list_close(void);   /* 0 */

/* Reads a line from the tty with no echo into a static buffer, or "" if there
 * is no tty or nothing was read. */
const char *granular_read_secret(const char *prompt);

/* Creates path as a 0700 directory owned by the caller. Returns 0 on success; -1 if it
 * exists as anything else (a symlink, a file, another user's directory). */
int granular_private_dir(const char *path);

/* Connects to the daemon's socket at path. Returns an fd, -1 if there is no daemon, or -2 if the socket
 * or the directory holding it is not private to the caller (not owned by them, or open to others). */
int granular_fetch_socket(const char *path);

/* Unix socket primitives for the daemon. Return an fd, or -1 on error. */
int granular_listen(const char *path);   /* removes a stale socket, mode 0600 */
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

/* Runs the executable at path with env_name set to value (an empty value removes it) and this
 * program's original arguments. Returns -1 if it could not be run. */
int granular_exec(const char *path, const char *env_name, const char *value);

/* Pid of the process on the other end of a connected socket, or -1. */
int granular_peer_pid(int fd);

/* One newline-terminated line (newline stripped) from a static buffer, "" on EOF or error. */
const char *granular_read_line(int fd);
int granular_write_line(int fd, const char *s);   /* 0 on success */

/* Creates or updates the item, with description stored on it ("" for none). Returns 0 on success. */
int granular_kc_set(const char *service, const char *account, const char *secret, const char *description);

#endif
