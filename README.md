# granular_git

Install and uninstall: [INSTALL.md](INSTALL.md).
Day-to-day use of each program: [USAGE.md](USAGE.md).
Build, tests and release: [DEVELOPING.md](DEVELOPING.md).

## Start here

macOS. In your own terminal, download `granular-<version>-<arch>.tgz` from the [latest release](https://github.com/kbrock/granular-git/releases/latest), then:

    sudo tar xzf granular-*.tgz -C /usr/local/bin
    granular-audit

`granular-audit` lists what is left to set up. [INSTALL.md](INSTALL.md) has the tokens, the daemon and upgrades.

## Before

Once you enter your GitHub or GitLab token into git, any process on your machine has full access. So Claude can push, delete, or do anything you have permission to do.

## After

You create two tokens, one read-only and one read-write. Your shell gets read-write, and Claude gets read-only.

When you want Claude to update a PR, toggle the permission for that process. Claude can then use `git` or `gh` to write to GitHub. When you are done, toggle it off.

This does not use Claude Code's permissions or LLM rules. It restricts Claude at GitHub itself, and it works in auto mode.

It is a gentle guard: it limits what Claude can push when it misreads your goal. [What it does not stop](#what-it-does-not-stop) lists the gaps.

## How it decides

Git asks a credential helper for a token. The helper finds out who is asking. It starts with the calling process, compares the program name or the pid against a table of rules, and walks up the parent processes until one matches. The match names a profile, and the profile holds the token.

A process that matches nothing gets the read-only token. This includes a process that left Claude's chain with a double fork.

Out of the box:
- `claude` and `Claude.app` get the read-only token.
- `login`, `sshd-session` and Sublime Merge get the read-write token. Terminal tabs run under `login` and ssh sessions under `sshd-session`, so your own shells get read-write.

The tool ships two profiles, `ro` (read-only) and `rw` (read-write). You can add more.

## Parts

- **`granular-git`**: the git credential helper. Git runs it, and it answers with a token or nothing.
- **`gh`**: a wrapper placed ahead of the real `gh` on the PATH. It runs the real `gh` with the caller's token for that one call.
- **`granular-daemon`**: optional. Answers the helper and the wrapper over a socket, shows every request, and lets you change the table while it runs.
- **`granular-trust`**: shows the chain of processes above you.
- **`granular-passwd`**: stores, rekeys and exports the tokens.
- **`granular-audit`**: checks that the machine is set up correctly.

## Tokens and the vault

Tokens live in a keychain file of their own, `~/Library/Keychains/granular.keychain-db`, with its own password. Each login is an item named `granular:<profile>:<host>`, and macOS asks you to approve each item once.

- Tokens are not in a config file, the helper or the daemon's code.
- One caller's token is never cached for another.
- Any host works when the vault holds an item for it under the caller's profile.

## Levels of control

1. **Rules only.** No daemon runs. The helper applies the rules above in its own process. `claude` is the one blacklisted program.
2. **The daemon.** Start it to see each request and its chain, view the table, and change a rule or a running process. Details are in [USAGE.md](USAGE.md).
3. **Named shells.** Turn off the `login` and `sshd-session` rules in the daemon, then give read-write only to the shells you name. This is the stronger setting.

## What it does not stop

The system assumes a well-behaved environment. Claude can skip an instruction. It does not attack the machine.

- Claude runs as you. It can kill the daemon, write under `~/.granular`, or type into the daemon's tab.
- Claude can start a session of its own, for example with `ssh localhost` or `open -a Terminal`. That session runs under `login` and gets read-write. Level 3 closes this, and a separate macOS user closes it fully.
- The read-write token is a classic `repo` token. It covers every repo the account can push to.
- A process whose program file was replaced while it ran has no readable path. It gets read-only.
- `Claude.app`'s own terminal panel descends from `Claude.app`, so it gets read-only. Flip it in the daemon.
- Nested `claude` processes: the nearest one decides.
- A Keychain dialog blocks the daemon until it is answered.
- The Spinel build holds the token in a Ruby string and does not wipe it.
- A binary signed with a different identity prompts once per item. Rekey the items to stop that.
- The `gh` wrapper covers github.com only.

## Built with

Ruby compiled to a native binary by Spinel, plus a small C shim for the Security framework and process calls.
