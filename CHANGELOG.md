# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-11-10

### Added
- `granular-git`, a Git credential helper. A process under `claude` gets the `ro` token and everything else gets the `rw` token, decided by the caller's process ancestry.
- `granular-daemon`, which keeps a table of nodes: a pid with its start time, plus two catch-alls for every process under pid 1 and every process not under it. Typing a node number in the daemon's tab moves that node to the next profile, and a new profile name joins the cycle.
- A `gh` wrapper that runs the real `gh` with the caller's token. `gh auth status` prints the profile's message, and `gh auth token` is refused.
- `granular-passwd` stores a login in the vault with a message for the profile. `--rekey` re-adds an item from the current build, and `--stdin` reads the username and token from a pipe. It refuses to run under Claude.
- A keychain of its own for the tokens, `~/Library/Keychains/granular.keychain-db`.
- `granular-audit`, which checks the computer's setup and prints a fix for each failure, and prints the installed version.
- `granular-test-ro` and `granular-test-rw`, which check what each profile can do.
- `make dist`, which builds `build/granular-<version>.tgz` with the installed files, for a computer without Spinel.
- `granular-git --version`.

[Unreleased]: https://github.com/kbrock/granular-git/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/kbrock/granular-git/releases/tag/v0.1.0
