# granular_git

## 1. Goal

Claude Code has pushed code several times after being told not to. The existing macOS Keychain credential helper is set to "always allow Git", so any process on the machine, including Claude Code, can use the read-write GitHub token. The fix must not depend on Claude following instructions or on Git hooks.

Use AI more without granting it permissions forever. Claude's permissions are granular: it gets only what a task needs, Buster adds and removes them on the fly, and flipping a permission back is a first-class action. No blanket allow. The end state is a Claude with more permissions than today, each one granted on purpose.

Claude Code can never push to GitHub. Which token Git receives decides it, not Claude following instructions.
Your own terminal pushes with no extra steps.

TODO: add wording here.

## 2. Mechanism

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

## 3. Acceptance criteria

Each mark must be turned into a runnable check (exact command, test repository, expected exit code or message).

**Git and `gh` credentials (1A and 1B)**
1. `git push` from Buster's terminal succeeds with the read-write token.
2. `git push` inside a Claude Code session fails with an authentication error (non-zero exit). Claude receives the read-only token.
3. The same results hold when Git is run indirectly: Python subprocess, shell script, nested sub-agent.
4. No token appears in Claude's environment variables or in any command output Claude can see. A direct Keychain read by Claude, not through the daemon, triggers a prompt.
5. Any Keychain prompt makes it obvious who is asking. A prompt from the daemon is recognizable by a distinct binary name.
6. No repeated prompts on normal Git commands, from his terminal or from Claude.

**Hook for Git commands (1C)**
7. The hook intercepts a Git command before it runs and asks the daemon.
8. A denied command (for example `git rebase`) is blocked and Claude sees a clear reason.
9. An allowed command runs with no prompt.

**Per-session overrides (1D)**
10. One session can be granted an action (for example merge into master) while a second concurrent session stays denied.
11. An override applies only to the session it was set for and ends when that session ends.

## 4. What a prompt is

A prompt is the macOS dialog that appears when a program asks to read a Keychain item. A new build of granular triggers one the first time it reads each token.

It reads: "granular wants to use your confidential information stored in 'granular:ro:github.com' in your keychain", and asks for a keychain password.
- Allow: this read only. It asks again next time.
- Always Allow: remembered for this build of the binary.
- Deny: refuses the read.

What to press:
- Allow or Always Allow a prompt that names `granular` and `granular:ro:github.com` or `granular:rw:github.com`.
- Deny a prompt that names anything else, such as `security` or `nc`. Something else is asking for a token.

A prompt appears once per binary per item (`ro` and `rw` are two items). A signed rebuild keeps the approval. A new signing identity brings the prompts back until you rekey.

## 5. Basic mode, no daemon

In your own terminal. On the computer with Spinel:
```
make dist    # builds build/granular.tgz
```
On the computer you are setting up:
```
cd ~/Downloads
scp src:src/granular-git/build/granular.tgz .
# basically Spinel's make install
sudo mkdir -p /usr/local/bin && sudo tar xzf granular.tgz -C /usr/local/bin
[ -x /usr/local/bin/granular ] && echo "installed"

# transfer github password to protected vault
# copy and paste each line. macOS asks to read the item: click Allow, never Always Allow
user=$(security find-internet-password -s github.com | sed -n 's/.*"acct"<blob>="\(.*\)"/\1/p')
pw=$(security find-internet-password -s github.com -w)
# first time: you will enter a password for your vault. this is similar to an aws-vault setup
printf '%s\n%s\n' "$user" "$pw" | granular-passwd --stdin rw github.com
unset pw

# clear password from system vault (checks that you have it before deleting)
security find-generic-password -s granular:rw:github.com ~/Library/Keychains/granular.keychain-db >/dev/null && printf "protocol=https\nhost=github.com\n\n" | git credential-osxkeychain erase
```

### Create tokens

`gh` cannot create tokens. Use the web UI.

1. Create the `ro` token. Claude gets this one.
   a. Open https://github.com/settings/personal-access-tokens/new
   b. Name `granular-ro`. Resource owner: you (or company). Repository access: All repositories. Permissions: Contents, Pull requests and Issues, each read. Click Generate token and copy it.
   c. `granular-passwd ro github.com "You don't currently have access to push to github. Stop and ask for access."`
      Enter your GitHub username, then paste the token.
2. Create the `rw` token. Your terminal gets this one.
   a. Open https://github.com/settings/tokens/new
   b. Note `granular-rw`. Tick `repo`. Click Generate token and copy it.
   c. `granular-passwd rw github.com`
      Enter your GitHub username, then paste the token.

2b. Create a fine-grained `rw` token instead. It pushes to one owner.
   a. Open https://github.com/settings/personal-access-tokens/new
   b. Name `granular-rw`. Resource owner: the owner you push to. Repository access: Only select repositories. Permissions: Contents and Pull requests, each read and write. Click Generate token and copy it.
   c. `granular-passwd rw github.com`
      Enter your GitHub username, then paste the token.

### Audit and test

Each FAIL prints its fix. Run the fixes and the audit again until none fail:
```
granular-audit
```
In a clone of a repo you can push to (sections 9 to 11):
```
granular-test-rw    # in your terminal
granular-test-ro    # in a Claude session
```

Git and `gh` now decide in their own process: a `claude` above them gets `ro`, anyone else gets `rw`.
- You gain: Claude's pushes fail and yours work, with nothing else running.
- You lose: no per-process flipping, and no record of who asked.

## 6. Add the daemon

Type `granular-daemon` in a spare terminal tab and leave it running.

Git and `gh` now ask the daemon over `~/.granular/sock`, and only the daemon reads the Keychain for them. Every request prints the caller's chain on one line, outermost first, with a node number on each process that can carry a profile:
`login > zsh [3] > claude [2] > node > git > git-remote-https: ro`

- The daemon decides by the profile table (see Mechanism). The first process with a profile decides: a node you moved, else an app name (seeded for `claude` and `Claude.app`). With none the caller gets the default node (`rw`).
- Nodes 2 to 10 go to every matched process the daemon sees and to the outermost shell above it.
- Type a node number and Enter in the daemon's tab to move that node to the next profile. Enter alone lists the nodes with their pid and working directory. A process shows only after it has made a request or the scan has found a `claude` by name.
- Node 0 is `not under pid 1` and node 1 is `under pid 1`. Moving node 1 changes what a process with no node of its own gets.
- Type a new profile name (a letter, then letters, digits, `-` or `_`) and Enter to add it to the end of the cycle. Store its token with `granular-passwd <name> github.com`. A profile with no token answers `deny no item`.
- A node is freed when its process exits, and its number is reused.

- You gain: flip one Claude session to `rw` for a task and flip it back, and a line for every request.
- You lose: one more process to keep running. A Keychain dialog blocks the daemon until it is answered.

## 7. The vault

The tokens live in a keychain file of their own, `~/Library/Keychains/granular.keychain-db`, with its own password.

The first `granular-passwd` run creates it, through a system dialog that asks for the password. The password stays out of this program.

- It relocks after a day and stays unlocked through sleep. Unlock it from any terminal: `security unlock-keychain ~/Library/Keychains/granular.keychain-db`
- Each login is an item: service `granular:<profile>:<host>`, account the username, secret the token. Git and `gh` share them.
- Rekey an item: `granular-passwd --rekey <profile> <host> [description]` reads the stored login, deletes the item and adds it again from the current build. Run it when a vault item prompts after a rebuild or a change of signing identity, because an item's access list names the build that stored it. It also changes the message with no token to paste: a given description replaces the old one, `""` clears it, and none keeps it.

- You gain: the tokens sit apart from the rest of your login keychain.
- You lose: a second password, and a locked vault gives no token until you unlock it.

## 8. Audit

`granular-audit` asks: is this computer configured correctly? It changes nothing. A failure means the environment is wrong, not the program.

Steps:
1. Open your own terminal, not Claude.
2. If you use the daemon, start `granular-daemon` in another tab.
3. Run `granular-audit`.
4. For each failure the audit says what went wrong and prints the fix. Apply it, then run the audit again until nothing fails.

Some checks read the vault, so a prompt can appear (see What a prompt is). The script exits 1 if any check fails.

## 9. Test branch (once)

The tests run in the repo you are standing in, on its current branch. Make a branch for them, so they never touch your working branches. The repo needs an `https://github.com` origin, and you need push access.

Steps:
1. Have the `ro` and `rw` tokens stored in the vault (Basic mode, steps 2 and 3).
2. Create the branch: `git switch -c granular-test`
3. In your own terminal, publish it once, so it has an upstream: `git push -u origin granular-test`
   On a public repo the branch is visible.
4. Run the tests below from this branch. They run `git push --dry-run` and change nothing on GitHub.
5. When you are done: `git switch -`, then `git branch -D granular-test` and `git push origin --delete granular-test`

## 10. Test: granular-test-ro

`granular-test-ro` asks: does the read-only profile do what we want? It changes nothing on GitHub; the push is a dry run.

Steps:
1. Start `claude` on the test branch from section 9. A terminal whose node you moved to `ro` also works.
2. Ask Claude to run `granular-test-ro`.

Checks (PASS or FAIL for each; the script exits 1 if any fails):
- Push is refused.
- Push says write access is not granted.
- `gh` can read.
- The `gh` token has no `repo` scope.

## 11. Test: granular-test-rw

`granular-test-rw` asks: does the read-write profile do what we want? It changes nothing on GitHub; the push is a dry run.

Steps:
1. Open your own terminal on the test branch from section 9. A Claude session whose node you moved to `rw` also works.
2. Run `granular-test-rw`.

Checks (PASS or FAIL for each; the script exits 1 if any fails):
- Push is accepted.
- Push is not refused for write access.
- `gh` can read.
- The `gh` token has the `repo` scope.

## 12. Test: flipping

A flip is checked by running the two tests either side of it, in one Claude session on the test branch from section 9. A Claude session starts at `ro`. For a terminal, move its node to `ro` first. The flip needs the daemon.

Steps:
1. Start `granular-daemon` in another tab. In the session, run `granular-test-ro`. It passes.
2. In the daemon's tab, type the session's node number and press Enter. The session is now `rw`.
3. In the session, run `granular-test-rw`. It passes.
4. Type the node number again. The session is `ro`. Run `granular-test-ro`. It passes.

## 13. Limitations

- The helper answers only `host=github.com`. Other hosts get no helper and git prompts in the terminal.
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

## 14. Uninstall

Copy and paste each line.
```
# copy rw back to the system vault (asks for your vault password)
vault=~/Library/Keychains/granular.keychain-db
user=$(security find-generic-password -s granular:rw:github.com $vault | sed -n 's/.*"acct"<blob>="\(.*\)"/\1/p')
pw=$(security find-generic-password -s granular:rw:github.com -w $vault)
printf 'protocol=https\nhost=github.com\nusername=%s\npassword=%s\n\n' "$user" "$pw" | git credential-osxkeychain store
unset pw

# stop the daemon (Ctrl-C in its tab), then remove everything
rm -rf ~/.granular
sudo rm /usr/local/bin/{granular,granular-git,granular-passwd,granular-daemon,gh,granular-audit,granular-test-ro,granular-test-rw}
git config --global --unset-all credential.helper
git config --global --add credential.helper osxkeychain
brew link gh    # then: gh auth login

# delete the vault. cannot be undone: the tokens are gone
# security delete-keychain ~/Library/Keychains/granular.keychain-db
```
Revoke the `ro` and `rw` tokens at https://github.com/settings/tokens

## 15. Developer

- Compile: `make link`. Install: `make install`. Remove: `make uninstall`. Clean: `make clean`.
- Run all three tests after every build. A rebuild signed with the same identity does not prompt again.
- Switches at the top of `granular.rb`. Rebuild after changing one.
  - `VAULT`: the keychain file in `~/Library/Keychains`.
  - `REQUIRE_DAEMON`: default `false`. `true` makes Git and `gh` give no token when the daemon is not running.
  - `REAL_GH`: the real `gh`, default `/opt/homebrew/opt/gh/bin/gh`. On an Intel Mac use `/usr/local/opt/gh/bin/gh`.
  - `APP_PROFILES`, `DEFAULT_PROFILE`: the table entries.
