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
1. A process row: pid plus start time (the start time tells a reused pid apart). The slots are the process rows. Flipping a slot sets its row.
2. An app row: the executable's file name. `claude` (the CLI) and `Claude` (`Claude.app`) get the profile.
3. The default row.

Seeded rows: the `claude` CLI and `Claude.app` map to `ro`. Default maps to `rw`. A chain that does not reach launchd gets `ro`. The table lives in the daemon's memory only; a daemon restart returns it to the seed.

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

Not started. `granular-trust` sets the profile of a process by pid, so each Claude Code session carries a profile of its own, and the row ends when the process exits. Setting a profile is a request that the caller's profile allows or denies, and Claude's profile denies it. Rules can also differ per session through the sub-agent ID in the hook input. Examples:
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

Type these in your own terminal.

1. `make install`. The first build creates a signing identity, and macOS asks for your login password. The identity signs the binaries so the Keychain's "Always Allow" survives a rebuild. `granular` and its links (`granular-git`, `granular-passwd`, `granular-daemon`, `gh`) land in `/usr/local/bin`.
2. Create and store the `ro` token. Claude gets this one. `gh` cannot create personal access tokens, so use the web UI.
   a. Open https://github.com/settings/personal-access-tokens/new
   b. Token name `granular-ro`. Pick an Expiration. Resource owner: you. Repository access: All repositories.
      Under Permissions, Repositories, add Contents, Pull requests and Issues, each with read access.
      Click Generate token and copy it.
   c. In your terminal:
      `granular-passwd ro github.com "You don't currently have access to push to github. Stop and ask for access."`
      Enter your GitHub username, then paste the token. The command refuses to run under Claude. The first run creates the vault, and a system dialog asks for its password. The item is `granular:ro:github.com`. The message is printed on stderr whenever the helper serves this profile. `granular-passwd -h` lists the forms.
3. Create and store the `rw` token. This one reaches every repo your account can push to.
   a. Open https://github.com/settings/tokens/new
   b. Note `granular-rw`. Pick an Expiration. Tick `repo`, plus `workflow`, `gist` or `read:org` if used.
      Click Generate token and copy it.
   c. In your terminal: `granular-passwd rw github.com`. The item is `granular:rw:github.com`.

3b. Create a fine-grained `rw` token instead. It pushes to one owner.
    a. Open https://github.com/settings/personal-access-tokens/new
    b. Token name `granular-rw`. Pick an Expiration. Resource owner: the owner you push to. Repository access: Only select repositories, then pick them. Under Permissions, Repositories, add Contents and Pull requests, each with read and write access. Click Generate token and copy it.
    c. In your terminal: `granular-passwd rw github.com`. The item is `granular:rw:github.com`.
    Repos owned by another user are out of reach for this token.

4. Run `granular-audit`. Both items appear under "vault", with the account name and never a token.
5. Point Git at the helper in `~/.gitconfig`, with an absolute path:
   `[credential]`, then `helper =` (empty, clears every earlier helper), then `helper = /usr/local/bin/granular-git`
   Remove any other `credential.helper` lines from your config files.
6. Take brew's `gh` off PATH: `rm /opt/homebrew/bin/gh`
7. Remove the credential `gh` holds itself: `gh auth logout -h github.com`
8. Check the profiles with the tests in sections 9 to 11: `granular-test-rw` in your terminal, `granular-test-ro` inside a Claude session, both on the test branch from section 9. They only read and run `git push --dry-run`, so they change nothing on GitHub.

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
- Type `0` and Enter to flip the default (`DEFAULT_PROFILE`) between `ro` and `rw`. The default applies to a process with no slot and no table row.
- A slot is freed when its process exits, and its number is reused.

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
1. Start `claude` on the test branch from section 9. A terminal whose slot you flipped to `ro` also works.
2. Ask Claude to run `granular-test-ro`.

Checks (PASS or FAIL for each; the script exits 1 if any fails):
- Push is refused.
- Push says write access is not granted.
- `gh` can read.
- The `gh` token has no `repo` scope.

## 11. Test: granular-test-rw

`granular-test-rw` asks: does the read-write profile do what we want? It changes nothing on GitHub; the push is a dry run.

Steps:
1. Open your own terminal on the test branch from section 9. A Claude session whose slot you flipped to `rw` also works.
2. Run `granular-test-rw`.

Checks (PASS or FAIL for each; the script exits 1 if any fails):
- Push is accepted.
- Push is not refused for write access.
- `gh` can read.
- The `gh` token has the `repo` scope.

## 12. Test: flipping

A flip is checked by running the two tests either side of it. Run them from the process you will flip, a Claude session or a terminal, on the test branch from section 9.

Steps:
1. Start `granular-daemon` in another tab. In the process, run `granular-test-ro`. It passes.
2. In the daemon's tab, flip this process to `rw`.
3. Run `granular-test-rw`. It passes.
4. Flip the process back to `ro` and run `granular-test-ro` again. It passes.

## 13. Limitations

- The helper answers only `host=github.com`. Other hosts get no helper and git prompts in the terminal.
- An orphaned process (double fork) reparents to launchd, loses `claude` from the chain, and receives the default profile (`rw`).
- The `rw` token is a classic `repo` token, so a slot flipped to `rw` gives Claude every repo the account can push to.
- The Spinel build holds the token in a Ruby string and does not wipe it.
- A Keychain dialog blocks the single-threaded daemon until it is answered. The client waits 60 seconds for a reply. The daemon waits 2 seconds for a request.
- A rebuild signed with the same identity keeps the approvals. `brew upgrade` changes the binary and prompts again once per item.
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
- Run all three tests after every build. A rebuild signed with the same identity does not prompt again.
- Switches at the top of `granular.rb`. Rebuild after changing one.
  - `VAULT`: the keychain file in `~/Library/Keychains`.
  - `REQUIRE_DAEMON`: default `false`. `true` makes Git and `gh` give no token when the daemon is not running.
  - `REAL_GH`: the real `gh`, default `/opt/homebrew/opt/gh/bin/gh`. On an Intel Mac use `/usr/local/opt/gh/bin/gh`.
  - `APP_PROFILES`, `DEFAULT_PROFILE`: the table rows.
