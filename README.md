# granular_git

Goal: Claude Code can never push to GitHub. Which token Git receives decides it, not Claude following instructions.
Your own terminal pushes with no extra steps.
Written in Spinel (Ruby compiled to a native binary), with a small C shim for the Keychain and process calls.
Build: `make link`. Install: `make install`. Remove: `make uninstall`.

## Setup

1. Run `make install`. `granular` and its links (`granular-git`, `granular-passwd`, `granular-daemon`, `gh`) land in `/usr/local/bin`.
2. Create two GitHub tokens:
   - `ro`: fine-grained, owner you, All repositories, with Contents, Pull requests and Issues read-only. Claude gets this one.
   - `rw`: classic with the `repo` scope, plus `workflow`, `gist` or `read:org` if you use them. It reaches every repo your account can push to. A fine-grained token has one owner and cannot reach repos owned by another user.
3. Store each from your own terminal. The command refuses to run under Claude. Enter your GitHub username, then paste the token.
   `granular-passwd ro github.com` and `granular-passwd rw github.com`
   Each login is a Keychain item: service `granular:<profile>:<host>`, account the username, secret the token. Git and `gh` share them.
4. Point Git at the helper in `~/.gitconfig`, with an absolute path:
   `[credential]`, then `helper =` (empty, clears every earlier helper), then `helper = /usr/local/bin/granular-git`
   Remove any other `credential.helper` lines from your config files.
5. Keep `/usr/local/bin` ahead of `/opt/homebrew/bin` on your PATH. Its `gh` link gets the caller's token and runs the real `gh` with it.
6. Remove the credential `gh` holds itself: `gh auth logout -h github.com`. The wrapper runs `gh auth ...` commands without a token, so they act on `gh`'s own credential.
7. Start `granular-daemon` in a terminal tab and leave it running.

## Modes

`USE_DAEMON` at the top of `granular.rb` selects the mode. Rebuild after changing it.
- `true` (default): Git and `gh` ask `granular-daemon` over `~/.granular/sock`, and only the daemon reads the Keychain. Without a running daemon they fail closed.
- `false`: each program walks its own ancestry and reads the Keychain itself. There are no slots.

## The daemon

Every request prints the caller's chain on one line, outermost first, with a slot number on each process that can carry a profile:
`login > zsh [2] > claude [1] > node > git > git-remote-https: ro`
- Slots 1 to 9 go to every `claude` and to the outermost shell with no `claude` above it.
- Type a slot number and Enter in the daemon's terminal to flip that process between `ro` and `rw`. Enter alone lists the slots with their pid and working directory.
- The nearest flipped process above the caller decides. With none flipped, a `claude` caller gets `ro` and anyone else gets `rw`. A chain that does not reach launchd gets `ro`.
- A slot is freed when its process exits, and its number is reused.

## Audit

Run `./audit.sh` from your own terminal. It changes nothing, prints PASS or FAIL for each check, and prints the fix for each failure. It covers the Git helper chain, the chosen mode, the saved GitHub item in the Apple keychain, the credentials `gh` holds, whether the install directory is on PATH ahead of `/opt/homebrew/bin`, and the `gh` link. Some checks read your login, so a Keychain prompt can appear.

## Keychain prompts

A prompt reads: "granular wants to use your confidential information stored in 'granular:ro:github.com' in your keychain", and asks for your login keychain password.
- It appears once per binary per item (`ro` and `rw` are two items), and again after each rebuild.
- Allow a prompt that names `granular` and `granular:ro:github.com` or `granular:rw:github.com`.
- Deny a prompt that names anything else, such as `security` or `nc`.
- Always Allow remembers the choice for that build of the binary. Allow asks again on the next read.
- Build once, store the tokens, then use it. Each rebuild brings the prompts back.
