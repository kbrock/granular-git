# Developing

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

## 15. Developer

- Compile: `make link`. Install: `make install`. Remove: `make uninstall`. Clean: `make clean`.
- Run all three tests after every build. A rebuild signed with the same identity does not prompt again.
- Switches at the top of `granular.rb`. Rebuild after changing one.
  - `VAULT`: the keychain file in `~/Library/Keychains`.
  - `REQUIRE_DAEMON`: default `false`. `true` makes Git and `gh` give no token when the daemon is not running.
  - `REAL_GH`: the real `gh`, default `/opt/homebrew/opt/gh/bin/gh`. On an Intel Mac use `/usr/local/opt/gh/bin/gh`.
  - `APP_PROFILES`, `DEFAULT_PROFILE`: the table entries.
- Release. Put the changes under `[Unreleased]` in `CHANGELOG.md`, then:
  ```sh
  bin/bump                         # on the feature branch: suggests the version, commits "Release X"
  # merge the branch into main
  git checkout main && git pull
  make release                     # builds the tarball and .sha256, gh tags vX and attaches both
  ```
  Run `make release` in your own terminal: it needs the `rw` token. `make release REMOTE=upstream` uses another remote.
