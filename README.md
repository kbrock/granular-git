# granular_git

Install and uninstall: [INSTALL.md](INSTALL.md).
Tests and release: [DEVELOPING.md](DEVELOPING.md).

## Goal

Grant git keys per shell or Claude session. So you can let claude temporarily read from github
You can also change the permissions turn by turn so granting a git push once doesn't allow it forever.

## Mechanism

Think per process claude code hooks, but in git itself.

A central daemon listens on a Unix domain socket. Callers connect and ask "can I do this". The daemon resolves the caller's PID, walks its parent PIDs to identify the caller, and answers allow or deny.

### Programs

1. **Central daemon.** Listens on a Unix domain socket and is the only program with Keychain access.
2. **Git credential helper client.** Git launches it as a child process. It forwards the credential request to the daemon over the socket and returns the daemon's answer to Git.
3. **Claude Code hook command** (1C). Asks the daemon whether a command may run and returns allow or deny.
4. **`gh` PATH wrapper.** The only `gh` on the PATH. It asks the daemon who the caller is, receives the `ro` or `rw` token, then runs the real `gh` at `REAL_GH` with `GH_TOKEN` set for that one call.

### Technology

Spinel (Ruby ahead-of-time compiler that produces a standalone native binary by way of C), calling the Security framework (`SecItemCopyMatching`, `kSecClassGenericPassword`) and libproc through the C shim.

### Design constraints

- The C interface is minimal. A function is in C only when Spinel cannot do the work. Everything else is Ruby.
- The system assumes a well-behaved environment. Claude can skip an instruction. It does not attack the machine, so there is no lock-down mode.
- Profiles are user defined and have no order. Out of the box `claude` gets `ro` and every other caller gets `rw`.

### Caller identification

- Start from the caller's PID and climb parent PIDs all the way to PID 1. No early stop. This covers Python subprocesses, shell scripts and nested sub-agents without special cases.
- PID walk in C: `sysctl(KERN_PROC_PID)` for the parent PID, `proc_pidpath()` for the executable path.
- The daemon reads the caller PID with `getsockopt(SOL_LOCAL, LOCAL_PEERPID)`.

### Daemon

- `granular-daemon` listens on `~/.granular/sock` (directory 0700, socket 0600). Request `get <host> [user]`, reply `ok <user> <token> [description]` or `deny <reason>`. The description is the profile's message, which the client prints on stderr. Only `github.com` is a known host.
- `granular-git` and the `gh` wrapper ask the daemon first. With no daemon they decide in their own process, unless `REQUIRE_DAEMON` is `true`. A timeout or a non-`ok` reply exits 1 with no token.
- The daemon replies `deny vault locked` when the vault is locked.

### Profile table

A request walks up from the caller. The first process with a profile of its own decides, else the default applies:
1. A process node: pid plus start time (the start time tells a reused pid apart). Moving a process node sets its profile.
2. An app name: the executable's file name. `claude` (the CLI) and `Claude` (`Claude.app`) get the profile.
3. The default node (pid 1).

Seeded: the `claude` CLI and `Claude.app` map to `ro`. Node 0 stands for every process that is not a child of pid 1 (pid 0 is a pid no caller can have). It holds `ro` and applies to a chain that does not reach launchd, or that holds a process whose path cannot be read. Node 1 stands for every other process (pid 1) and holds `rw`. Nodes 2 to 10 are the processes. Profiles cycle in the order `ro`, `rw`, then any name added in the daemon's tab. The table lives in the daemon's memory only; a daemon restart returns it to the seed.

A profile holds the credentials for one target (GitHub, Gmail and others). A tool takes the credential of its own class from the profile it is given.

The Claude Code hook (1C) can return at once for commands that do not mention git, `gh` or `psql`.

### Token storage

- Two GitHub tokens, stored as `granular:<profile>:<host>` items with the username as the account, in the vault.
  - Read-only: fetch history, private repos, issues, PRs.
  - Read-write: create PRs and push. A classic `repo` token, so it covers every repo the account can push to.
- Tokens are never hard-coded in a helper or in the daemon.
- No credential caching across callers. A token fetched for his terminal must never be handed to a Claude process.

### Vault

Tokens live in a keychain file of our own, `~/Library/Keychains/granular.keychain-db`, with its own password. `VAULT` at the top of `granular.rb` names the file. The vault is required: the first `granular-passwd` run creates it. One keychain is searched, so there is no fallback and no config file.

- `granular_kc_*` opens the file with `SecKeychainOpen` and passes it as `kSecUseKeychain` on add and in `kSecMatchSearchList` on reads. Those calls are deprecated and still work for file keychains.
- `granular-passwd` creates the items in the vault. A read of a locked vault shows macOS's own unlock dialog, which names `granular` and the vault.

### Claude Code hook (1C)

Not started. A Claude Code hook (not a Git hook) runs before a shell command, calls the hook command, and the hook command asks the daemon "can I run command X". The daemon returns allow or deny. This step includes writing the full list of reasonable Git commands as allow or deny, so Buster can review it and flip individual entries.
- Default for Claude: local commands allowed (commit, squash, merge, and so on), network commands denied (fetch, pull, push).
- Whether Claude gets network read access (fetch, pull) is decided when the list is written.
- Buster's own terminal is unrestricted.
- Git hooks (such as pre-push and pre-rebase) are a low-probability backstop.
- The hook must set `onFailure` to block. A hook that crashes or times out does not block otherwise, so a daemon outage would let every Git command through.
- A PreToolUse deny holds even in bypass permissions mode.
- The hook must deny running the real `gh` by full path, which would bypass the PATH wrapper.
- The hook can match MCP tool names. The hook input format for MCP calls is unverified.

### Per-session overrides (1D)

Not started. `granular-trust` sets the profile of a process by pid, so each Claude Code session carries a profile of its own, and the node ends when the process exits. Setting a profile is a request that the caller's profile allows or denies, and Claude's profile denies it. Rules can also differ per session through the sub-agent ID in the hook input. Examples:
- One session may merge into master while a concurrent session may only merge into branches.
- Per-project config decides whether Claude commits to master or only to branches.
- Committing to master is separated from committing to a branch, and from merging master into a branch.

## Limitations

- The helper answers a host only when the vault holds a token for it under the caller's profile. Any other host gets no token and git prompts in the terminal. The `gh` wrapper covers github.com only.
- An orphaned process (double fork) reparents to launchd, loses `claude` from the chain, and receives the default profile (`rw`).
- The `rw` token is a classic `repo` token, so a node moved to `rw` gives Claude every repo the account can push to.
- The Spinel build holds the token in a Ruby string and does not wipe it.
- A Keychain dialog blocks the single-threaded daemon until it is answered. The client waits 60 seconds for a reply. The daemon waits 2 seconds for a request.
- A rebuild signed with the same identity keeps the approvals. `brew upgrade` changes the binary and prompts again once per item.
- Same-user processes, including Claude, can kill the daemon or write under `~/.granular`.
- A Claude process that connects to the socket itself gets `ro` by the same walk.
- Claude could type into the daemon's terminal to move its own node.
- `Claude.app`'s own Terminal panel descends from `Claude.app`, so the user's in-app terminal gets `ro`. A process node flips it.
- With the default `rw`, a terminal is not trusted, only not matched. Claude can script one (`osascript`, `open -a Terminal`), and the command runs outside its chain and gets `rw`. Running Claude as a separate user closes this.
- A process whose path cannot be read has no path and matches no node. From inside Claude's sandbox, the `claude` process is such a process.
- Nested `claude` processes: the nearest one decides.
