# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- `granular-git` no longer prints `store ignored` after a push. `store` and `erase` still do nothing, and INSTALL.md says so: add or change a token with `granular-passwd`.
- `granular-git` and `granular-passwd` work with any host, not only `github.com`. A host is served when the vault holds an item for it under the caller's profile. A host with no item prints `granular: no token for <host> profile <name>`, and git prompts.
- `granular-passwd --rekey --all` rekeys every item in the vault, whatever its host.

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
