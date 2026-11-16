# Developing

## Acceptance criteria

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

## Test branch (once)

The tests run in the repo you are standing in, on its current branch. Make a branch for them, so they never touch your working branches. The repo needs an `https://github.com` origin, and you need push access.

Steps:
1. Have the `ro` and `rw` tokens stored in the vault (Create tokens in [INSTALL.md](INSTALL.md)).
2. Create the branch: `git switch -c granular-test`
3. In your own terminal, publish it once, so it has an upstream: `git push -u origin granular-test`
   On a public repo the branch is visible.
4. Run the tests below from this branch. They run `git push --dry-run` and change nothing on GitHub.
5. When you are done: `git switch -`, then `git branch -D granular-test` and `git push origin --delete granular-test`

## Test: granular-test

`granular-test` reports which profile the caller gets, `rw` or `ro`. It changes nothing on GitHub; the push is a dry run, and it prints no tokens.

Steps:
1. Open the test branch from the Test branch section in the caller you want to check: your own terminal (expect `rw`) or a `claude` session (expect `ro`). A terminal whose node you moved to `ro` also works.
2. Run `granular-test`.

It prints four observations and the level:
- `push`: accepted or refused.
- `message`: whether the push said write access is not granted.
- `gh`: whether `gh` can read.
- `scope`: whether the `gh` token has the `repo` scope.

`level: rw` means accepted, no message, `gh` reads, `repo` scope. `level: ro` means refused, message shown, `gh` reads, no `repo` scope. Any other mix is `level: broken`, and the observations show which one disagrees.

With no flag the script exits 0 for `rw` or `ro` and 1 for `broken`. `granular-test --rw` and `granular-test --ro` exit 0 only if the level is that one.

## Test: flipping

A flip is checked by running the two tests either side of it, in one Claude session on the test branch from the Test branch section. A Claude session starts at `ro`. For a terminal, move its node to `ro` first. The flip needs the daemon.

Steps:
1. Start `granular-daemon` in another tab. In the session, run `granular-test --ro`. It passes.
2. In the daemon's tab, type the session's node number and press Enter. The session is now `rw`.
3. In the session, run `granular-test --rw`. It passes.
4. Type the node number again. The session is `ro`. Run `granular-test --ro`. It passes.

## Attack scripts

`test/support/` holds scripts that try to get around the rules. Run them from a Claude session on the test branch.
- `double-fork.sh` runs `granular-test --ro` in an orphaned process and prints `BLOCKED` or `ATTACK WORKS`.
- `unreadable-node.sh` runs a `claude` whose program file is deleted, and shows the process in the daemon's tab.

## Layout

- `granular.rb`: the C function table and the entry point. `lib/granular/*.rb`: one class per file, wired together by `Cli`.
- Three concepts, each in its own place. `Table` decides the profile for a process. `Responder` and `Vault` give the key for a profile and host. `Can` says whether a profile may run a command.
- Lint: `bundle exec rubocop`. `rubocop_spinel` flags Ruby that Spinel does not compile.

## Build and release

- Build: `make` (lint, compile, sign, then `bin/ci`). Install: `make install` (copies, then runs `granular-audit`). Remove: `make uninstall`. Tarball: `make dist`. Publish: `make release`. Clean: `make clean`.
- `make` signs quietly; check with `codesign -dvv build/granular` (Authority `Apple Development`, TeamIdentifier your Team ID). The links (`granular-git`, `gh`, ...) are files in `build/`; `make install` and `make dist` take the binary and links from there and the scripts from the repo root.
- `bin/ci` is the check after a build, one line per step. Under Claude it checks that `ro` holds and says to run the rest in your own terminal. In your own terminal it also checks `rw`, with no daemon and through a test daemon on `GRANULAR_SOCKET`. `make release` needs the full run to pass.
- After a rebuild, restart `granular-daemon`, then run `granular-test --rw` in your own terminal. A rebuild signed with the same Team ID does not prompt again.
- Switches in `lib/granular/config.rb`. Rebuild after changing one.
  - `VAULT`: the keychain file in `~/Library/Keychains`.
  - `REQUIRE_DAEMON`: default `false`. `true` makes Git and `gh` give no token when the daemon is not running.
  - `REAL_GH`: the real `gh`, default `/opt/homebrew/opt/gh/bin/gh`. On an Intel Mac use `/usr/local/opt/gh/bin/gh`.
  - `Table#initialize` in `lib/granular/table.rb`: the starting rules of the table (the root, and the rules by program name or path).
- Release. Put the changes under `[Unreleased]` in `CHANGELOG.md`, then:
  ```sh
  bin/bump                         # on the feature branch: suggests the version, commits "Release X"
  # merge the branch into main
  git checkout main && git pull
  make release                     # builds the tarball and .sha256, gh tags vX and attaches both
  ```
  Run `make release` in your own terminal: it needs the `rw` token. `make release REMOTE=upstream` uses another remote.
