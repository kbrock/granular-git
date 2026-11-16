# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `granular-trust` prints your parent processes, one per line: the distance up from itself (`0`, `-1`, `-2`, ...), the name and the pid.
- `make` lints with rubocop, compiles, signs, and runs `bin/ci`. A failed step deletes the binary, so the next `make` starts over. `make install` copies the binary, its links and the scripts, then runs `granular-audit`; `make dist` tars the same files; `make release` runs `bin/release`.
- `bin/ci` checks a build, one line per step. Under Claude it checks `ro`; in your own terminal it also checks `rw`, with no daemon and through a test daemon.
- `bin/sign` signs with an Apple Development certificate and fails the build unless the requirement pins your Team ID. A rebuild no longer brings back the Keychain prompt. INSTALL.md says how to create the certificate.
- `granular-test` replaces `granular-test-ro` and `granular-test-rw`: `granular-test`, `--ro` or `--rw`.
- `GRANULAR_SOCKET` in the environment replaces the daemon's socket path.
- `bin/release` checks the tree, the changelog and `bin/ci`, then publishes the tarball.
- The source is `lib/granular/*.rb`, one class per file, checked by rubocop with `rubocop_spinel`.
- `test/support/double-fork.sh` runs `granular-test --ro` in an orphaned process, and `unreadable-node.sh` runs a `claude` whose binary is gone.

### Changed
- The daemon's profiles are one table of nodes. A request walks up from the caller, and the first process with a node that has a profile decides. Node 0 is the root and holds `ro`. An orphan from a double fork, a cron job, or a process whose path cannot be read ends at the root and gets `ro`. `login`, `sshd-session` and Sublime Merge get `rw` by path. `claude` and `Claude` get `ro` by name.
- The daemon's request line puts the profile after the process that decided it, and leads with `root [0]` when the root decided. It drops the `granular-daemon:` prefix and the trailing `granular`.
- `granular-git` no longer prints `store ignored` after a push. `store` and `erase` still do nothing, and INSTALL.md says so: add or change a token with `granular-passwd`.
- `granular-git` and `granular-passwd` work with any host, not only `github.com`. A host is served when the vault holds an item for it under the caller's profile. A host with no item prints `granular: no token for <host> profile <name>`, and git prompts.
- `granular-passwd --rekey --all` rekeys every item in the vault, whatever its host.
- `granular-audit` groups its checks under headings (`granular-git`, `credential.helper`, `granular-daemon`, `vault`, `stored credentials`, `gh`). A FAIL line says what is wrong, and the vault's items are listed under the vault.

## [0.2.0] - 2026-11-10

### Added
- `granular-passwd --export <profile> <host>` lets you move key back to the system keychain.
- `granular-passwd --rekey --all` rekeys every item, so you can prompt key access all at once.
- `granular git|passwd|daemon|gh ...`. run all sub-commands through granular
- `granular --version` prints the version.
- `make dist` writes a `.sha256` next to the tarball, and the install steps check it.
- The node list now shows `?claude` for a binary no longer on disk (i.e.: command was updated)

### Changed
- `granular-audit` - the `ro` fix includes the message.
- Uninstall documentaton no longer adds the `osxkeychain` helper back.
- The README says what the tool does not stop: a process Claude starts outside its own chain still gets `rw`.

### Fixed
- `granular-audit` no longer shows duplicate failures.
- `granular-daemon` A process whose path is unreadable, can be referenced and profile changed.

## [0.1.0] - 2026-11-10

### Added
- `granular-git`, a Git credential helper. A process under `claude` gets the `ro` token and everything else gets the `rw` token, decided by the caller's process ancestry.
- `granular-daemon`, allows you to change git permissions for running processes.
- A `gh` wrapper that runs the real `gh` with the caller's token. `gh auth token` doesn't hand Claude a token (Claude does't like this).
- `granular-passwd` stores a login in the vault with an optional message for the profile. `--rekey` allows you to change keys, messges, and signature. It refuses to run under Claude.
- A keychain of its own for the tokens, `~/Library/Keychains/granular.keychain-db`.
- `granular-audit`, which checks the computer's setup and prints a fix for each failure.
- `granular-test-ro` and `granular-test-rw` check the current shell's permission.
- `make dist` builds `build/granular-<version>.tgz` with the installed files, for a computer without Spinel.
- `granular-git --version`.

[Unreleased]: https://github.com/kbrock/granular-git/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/kbrock/granular-git/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/kbrock/granular-git/releases/tag/v0.1.0
