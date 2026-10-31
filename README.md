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

- `granular-daemon` listens on `~/.granular/sock` (directory 0700, socket 0600). Request `get <host> [user]`, reply `ok <user> <token>` or `deny <reason>`. Only `github.com` is a known host.
- `granular-git` and the `gh` wrapper ask the daemon first. With no daemon they decide in their own process, unless `REQUIRE_DAEMON` is `true`. A timeout or a non-`ok` reply exits 1 with no token.
- The daemon replies `deny vault locked` when the vault is locked.

### Profile table

A request walks up from the caller. The first process with a profile of its own decides, else the default applies:
1. A process row: pid plus start time (the start time tells a reused pid apart). The slots are the process rows. Flipping a slot sets its row.
2. An app row: the executable's file name. `claude` (the CLI) and `Claude` (`Claude.app`) get the profile.
3. The default row.

Seeded rows: the `claude` CLI and `Claude.app` map to `ro`. Default maps to `rw`. A chain that does not reach launchd gets `ro`. The table lives in the daemon's memory only; a daemon restart returns it to the seed.

A profile is a bundle of credentials (GitHub, Gmail and others). A tool takes the credential of its own class from the profile it is given.

The Claude Code hook (1C) can return at once for commands that do not mention git, `gh` or `psql`.

### Token storage

- Two GitHub tokens, stored as `granular:<profile>:<host>` items with the username as the account, in the vault.
  - Read-only: fetch history, private repos, issues, PRs.
  - Read-write: create PRs and push. A classic `repo` token, so it covers every repo the account can push to.
- Tokens are never hard-coded in a helper or in the daemon.
- No credential caching across callers. A token fetched for his terminal must never be handed to a Claude process.

### Vault

Tokens live in a keychain file of our own, `~/Library/Keychains/granular.keychain-db`, with its own password. `VAULT` at the top of `granular.rb` names the file. An empty `VAULT` uses the login keychain. One keychain is searched, never both, so there is no fallback and no config file. `vault-create.sh` creates the file: `security create-keychain`, `security set-keychain-settings -t 86400` (leaving out `-l` keeps it unlocked across sleep) and `security unlock-keychain`, which prompts on the tty and so works over ssh. Never use `-p`, which puts the password in `ps`.

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

Not started. Rules that differ per Claude Code session, using the sub-agent ID and other environment parameters from the hook input. The 1C command list is partitioned into about four tiers so groups can be enabled together. Examples:
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

A prompt appears once per binary per item (`ro` and `rw` are two items), and again after each rebuild. Build once, store the tokens, then use it.

## 5. Basic mode, no daemon

Type these in your own terminal.

1. `make install`. `granular` and its links (`granular-git`, `granular-passwd`, `granular-daemon`, `gh`) land in `/usr/local/bin`.
2. Create the vault, which holds the tokens (see The vault): `./vault-create.sh`. Type the password when `security` asks for it.
3. Create two GitHub tokens:
   - `ro`: fine-grained, owner you, All repositories, with Contents, Pull requests and Issues read-only. Claude gets this one.
   - `rw`: classic with the `repo` scope, plus `workflow`, `gist` or `read:org` if you use them. It reaches every repo your account can push to. A fine-grained token has one owner and cannot reach repos owned by another user.
4. Store each in the vault. Enter your GitHub username, then paste the token. The command refuses to run under Claude.
   `granular-passwd ro github.com`
   `granular-passwd rw github.com`
5. Point Git at the helper in `~/.gitconfig`, with an absolute path:
   `[credential]`, then `helper =` (empty, clears every earlier helper), then `helper = /usr/local/bin/granular-git`
   Remove any other `credential.helper` lines from your config files.
6. Take brew's `gh` off PATH: `rm /opt/homebrew/bin/gh`
7. Remove the credential `gh` holds itself: `gh auth logout -h github.com`

Git and `gh` now decide in their own process: a `claude` above them gets `ro`, anyone else gets `rw`.
- You gain: Claude's pushes fail and yours work, with nothing else running.
- You lose: no per-process flipping, and no record of who asked.

## 6. Add the daemon

Type `granular-daemon` in a spare terminal tab and leave it running.

Git and `gh` now ask the daemon over `~/.granular/sock`, and only the daemon reads the Keychain for them. Every request prints the caller's chain on one line, outermost first, with a slot number on each process that can carry a profile:
`login > zsh [2] > claude [1] > node > git > git-remote-https: ro`

- The daemon decides by the profile table (see Mechanism). The first process with a profile decides: a slot you flipped, else a table row (seeded for `claude` and `Claude.app`). With none the caller gets `DEFAULT_PROFILE` (`rw`).
- Slots 1 to 9 go to every matched process the daemon sees and to the outermost shell above it.
- Type a slot number and Enter in the daemon's tab to flip that process between `ro` and `rw`. Enter alone lists the slots with their pid and working directory. The slot list shows a process only after it has made a request or the scan has found a `claude` by name.
- A slot is freed when its process exits, and its number is reused.

- You gain: flip one Claude session to `rw` for a task and flip it back, and a line for every request.
- You lose: one more process to keep running. A Keychain dialog blocks the daemon until it is answered.

## 7. The vault

The tokens live in a keychain file of their own, `~/Library/Keychains/granular.keychain-db`, with its own password.

Create it once in your own terminal and type the password yourself:
`./vault-create.sh`
The first `granular-passwd` run also creates it, through a system dialog that asks for the password. The password stays out of this program.

- It relocks after a day and stays unlocked through sleep. Unlock it from any terminal: `security unlock-keychain ~/Library/Keychains/granular.keychain-db`
- To move a login you already stored in the login keychain: `granular-passwd --from-login ro github.com`. It copies the item into the vault and prints the command that deletes the old one.
- Each login is an item: service `granular:<profile>:<host>`, account the username, secret the token. Git and `gh` share them.

- You gain: the tokens sit apart from the rest of your login keychain.
- You lose: a second password, and a locked vault gives no token until you unlock it.

### The system keychain

An empty `VAULT` at the top of `granular.rb` keeps the tokens in the system (login) keychain instead.

TODO: what you gain and lose.

## 8. Audit

`./audit.sh` asks: is this computer configured correctly? It changes nothing. A failure means the environment is wrong, not the program.

Steps:
1. Open your own terminal, not Claude.
2. If you use the daemon, start `granular-daemon` in another tab.
3. Run `./audit.sh`.
4. For each failure the audit says what went wrong and prints the fix. Apply it, then run the audit again until nothing fails.

Some checks read the vault, so a prompt can appear (see What a prompt is). The script exits 1 if any check fails.

## 9. Test repo (once)

The tests need a GitHub repo you can push to. Set it up once. The tests look in `~/src/granular-git-test`; `GRANULAR_TEST_REPO` names another path.

Steps:
1. Have the `ro` and `rw` tokens stored in the vault (Basic mode, steps 3 and 4).
2. Create the repo, either way. Run these in your own terminal, so `gh` gets `rw`.
   - With `gh`:
     ```
     mkdir ~/src/granular-git-test && cd ~/src/granular-git-test
     git init -b main
     echo test > README && git add README && git commit -m "first commit"
     gh repo create granular-git-test --private --source=. --push
     ```
   - On github.com: create a private repo named `granular-git-test` with a README, then clone it, with `git` or with `gh`:
     ```
     git clone https://github.com/<you>/granular-git-test.git ~/src/granular-git-test
     gh repo clone <you>/granular-git-test ~/src/granular-git-test
     ```
3. Run the three tests below.

## 10. Test: test-ro.sh

`./test-ro.sh` asks: does the read-only profile do what we want? It changes nothing on GitHub; the push is a dry run.

Steps:
1. Start `claude` in the granular_git directory. A terminal whose slot you flipped to `ro` also works.
2. Ask Claude to run `./test-ro.sh`.

Checks (PASS or FAIL for each; the script exits 1 if any fails):
- Fetch works.
- Push is refused.
- Push says write access is not granted.
- `gh` can read.
- The `gh` token has no `repo` scope.

## 11. Test: test-rw.sh

`./test-rw.sh` asks: does the read-write profile do what we want? It changes nothing on GitHub; the push is a dry run.

Steps:
1. Open your own terminal. A Claude session whose slot you flipped to `rw` also works.
2. Run `./test-rw.sh`.

Checks (PASS or FAIL for each; the script exits 1 if any fails):
- Fetch works.
- Push is accepted.
- Push is not refused for write access.
- `gh` can read.
- The `gh` token has the `repo` scope.

## 12. Test: test-flip.sh

`./test-flip.sh` walks one process from `ro` to `rw`. It commits a `timefile` to the test repo and pushes it to GitHub once the process is `rw`.

Steps:
1. Start the daemon. Run the script from the process you will flip: a Claude session or a terminal.
2. The script asks you to make sure this process is `ro` in the daemon's tab. Do that, then press Enter.
3. The script appends the time to `timefile`, runs `git add timefile`, `git commit -m "updated time"` and `git push`.
4. The script asks you to flip this process to `rw`. Do that in the daemon's tab, then press Enter.
5. The script runs `git push` again.

Checks (PASS or FAIL for each; the script exits 1 if any fails):
- Push is refused at `ro`.
- Push works at `rw`.

## 13. Limitations

- The helper answers only `host=github.com`. Other hosts get no helper and git prompts in the terminal.
- An orphaned process (double fork) reparents to launchd, loses `claude` from the chain, and receives the default profile (`rw`).
- The `rw` token is a classic `repo` token, so a slot flipped to `rw` gives Claude every repo the account can push to.
- The Spinel build holds the token in a Ruby string and does not wipe it.
- A Keychain dialog blocks the single-threaded daemon until it is answered. The client waits 60 seconds for a reply. The daemon waits 2 seconds for a request.
- Each rebuild changes the binary and prompts again once per item. `brew upgrade` does the same.
- Same-user processes, including Claude, can kill the daemon or write under `~/.granular`.
- A Claude process that connects to the socket itself gets `ro` by the same walk.
- Claude could type into the daemon's terminal to flip its own slot.
- `Claude.app`'s own Terminal panel descends from `Claude.app`, so the user's in-app terminal gets `ro`. A process row flips it.
- With the default `rw`, a terminal is not trusted, only not matched. Claude can script one (`osascript`, `open -a Terminal`), and the command runs outside its chain and gets `rw`. Running Claude as a separate user closes this.
- A process whose path cannot be read has no path and matches no row. From inside Claude's sandbox, the `claude` process is such a process.
- Nested `claude` processes: the nearest one decides.

## 14. Uninstall

1. Stop `granular-daemon` (Ctrl-C in its tab) and remove `~/.granular`.
2. `make uninstall` removes `granular` and its links (`granular-git`, `granular-passwd`, `granular-daemon`, `gh`) from `/usr/local/bin`.
3. In `~/.gitconfig`, remove the empty `helper =` line and `helper = /usr/local/bin/granular-git`. Add `helper = osxkeychain` back if you want it.
4. Restore brew's `gh`: `brew link gh`, then `gh auth login`.
5. Delete the vault: `security delete-keychain ~/Library/Keychains/granular.keychain-db`.
6. Revoke the `ro` and `rw` tokens in GitHub's token settings.

## 15. Developer

- Compile: `make link`. Install: `make install`. Remove: `make uninstall`. Clean: `make clean`.
- Run all three tests after every build. Each rebuild changes the binary, so the Keychain prompts come back.
- Switches at the top of `granular.rb`. Rebuild after changing one.
  - `VAULT`: the keychain file in `~/Library/Keychains`. Empty uses the login keychain.
  - `REQUIRE_DAEMON`: default `false`. `true` makes Git and `gh` give no token when the daemon is not running.
  - `REAL_GH`: the real `gh`, default `/opt/homebrew/opt/gh/bin/gh`. On an Intel Mac use `/usr/local/opt/gh/bin/gh`.
  - `APP_PROFILES`, `DEFAULT_PROFILE`: the table rows.
