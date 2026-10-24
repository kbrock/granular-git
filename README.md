# granular_git

Goal: Claude Code can never push to GitHub. Which token Git receives decides it, not Claude following instructions.
Your own terminal pushes with no extra steps.
Written in Spinel (Ruby compiled to a native binary), with a small C shim for the Keychain and process calls.
Build: `make link`.

## Setup

1. Build with `make link`. The programs land in `build/`.
2. Create two fine-grained GitHub tokens limited to the repositories you want: `ro` (Contents: read-only) and `rw` (Contents: read and write).
3. Store each from your own terminal. The command refuses to run under Claude. Enter your GitHub username, then paste the token.
   `build/granular-passwd ro github.com` and `build/granular-passwd rw github.com`
   Each login is a Keychain item: service `granular:<profile>:<host>`, account the username, secret the token. Git and `gh` share them.
4. Point Git at the helper in `~/.gitconfig`, with an absolute path:
   `[credential]`, then `helper =` (empty, clears every earlier helper), then `helper = /path/to/build/granular-git`
   Remove any other `credential.helper` lines from your config files.
5. Put `build/shims` first on your PATH. It holds a `gh` that gets the caller's token and runs the real `gh` with it.
6. Remove the credential `gh` holds itself: `gh auth logout -h github.com`. The wrapper runs `gh auth ...` commands without a token, so they act on `gh`'s own credential.

## Modes

`USE_DAEMON` at the top of `granular.rb` selects the mode. Rebuild after changing it.
- `false` (default): each program walks its own ancestry and reads the Keychain itself.
- `true`: start `build/granular-daemon` in a terminal tab. Git and `gh` ask it over `~/.granular/sock`, and only the daemon reads the Keychain.

## Audit

Run `./audit.sh` from your own terminal. It changes nothing, prints PASS or FAIL for each check, and prints the fix for each failure. It covers the Git helper chain, the chosen mode, the saved GitHub item in the Apple keychain, the credentials `gh` holds, and the `gh` wrapper on PATH.

## Keychain prompts

A prompt reads: "granular wants to use your confidential information stored in 'granular:ro:github.com' in your keychain", and asks for your login keychain password.
- It appears once per binary per item (`ro` and `rw` are two items), and again after each rebuild.
- Allow a prompt that names `granular` and `granular:ro:github.com` or `granular:rw:github.com`.
- Deny a prompt that names anything else, such as `security` or `nc`.
- Always Allow remembers the choice for that build of the binary. Allow asks again on the next read.
- Build once, store the tokens, then use it. Each rebuild brings the prompts back.
