# Install

## What a prompt is

A prompt is the macOS dialog that appears when a program asks to read a Keychain item. A new build of granular triggers one the first time it reads each token.

It reads: "granular wants to use your confidential information stored in 'granular:ro:github.com' in your keychain", and asks for a keychain password.
- Allow: this read only. It asks again next time.
- Always Allow: remembered for this build of the binary.
- Deny: refuses the read.

What to press:
- Allow or Always Allow a prompt that names `granular` and `granular:ro:github.com` or `granular:rw:github.com`.
- Deny a prompt that names anything else, such as `security` or `nc`. Something else is asking for a token.

A prompt appears once per binary per item (`ro` and `rw` are two items). A signed rebuild keeps the approval. A new signing identity brings the prompts back until you rekey.

## Basic mode, no daemon

In your own terminal. On the computer with Spinel:
```sh
make dist    # builds build/granular-<version>.tgz and its .sha256
```
The first `make` runs `sign-identity.sh`, which makes a self-signed code-signing certificate in your login keychain and trusts it for code signing. macOS asks for your password.

On the computer you are setting up:
```sh
cd ~/Downloads
scp 'host:src/granular-git/build/granular-*' .
# basically Spinel's make install, after the checksum matches
shasum -a 256 -c granular-*.tgz.sha256 && sudo mkdir -p /usr/local/bin && sudo tar xzf granular-*.tgz -C /usr/local/bin
[ -x /usr/local/bin/granular ] && echo "installed"

# If you have a password in your System vault (if you use git you probably do)
# You can transfer github password to the new protected vault
# copy and paste each line. macOS asks to read the item: click Allow, not Always Allow
user=$(security find-internet-password -s github.com | sed -n 's/.*"acct"<blob>="\(.*\)"/\1/p')
pw=$(security find-internet-password -s github.com -w)
# first time: you will enter a password for your new vault. This is similar to an aws-vault setup
printf '%s\n%s\n' "$user" "$pw" | granular-passwd --stdin rw github.com
unset pw

# clear password from system vault (checks that you have it in new vault before deleting)
security find-generic-password -s granular:rw:github.com ~/Library/Keychains/granular.keychain-db >/dev/null && printf "protocol=https\nhost=github.com\n\n" | git credential-osxkeychain erase
```

### Create tokens

`gh` cannot create tokens. Use the web UI.

1. Create the `ro` token. Claude gets this one.
   a. Open https://github.com/settings/personal-access-tokens/new
   b. Name `granular-ro`. Resource owner: you (or company). Repository access: All repositories. Permissions: Contents, Pull requests and Issues, each read. Click Generate token, then the copy icon.
   c.
   ```sh
   granular-passwd ro github.com "You don't currently have access to push to github. Stop and ask for access."
   # enter your github username, Cmd-V to paste the token
   ```
2. Create the `rw` token. Your terminal gets this one.
   a. Open https://github.com/settings/tokens/new
   b. Note `granular-rw`. Tick `repo`. Click Generate token, then the copy icon.
   c.
   ```sh
   granular-passwd rw github.com
   # enter your github username, Cmd-V to paste the token
   ```

2b. Create a fine-grained `rw` token instead. It pushes to one owner.
   a. Open https://github.com/settings/personal-access-tokens/new
   b. Name `granular-rw`. Resource owner: the owner you push to. Repository access: Only select repositories. Permissions: Contents and Pull requests, each read and write. Click Generate token, then the copy icon.
   c.
   ```sh
   granular-passwd rw github.com
   # enter your github username, Cmd-V to paste the token
   ```

### Upgrade

Install the new tarball as above, restart the daemon, then rekey so the items name the new build:
```sh
granular-passwd --rekey --all
```

### Audit and test

Each FAIL prints its fix. Run the fixes and the audit again until none fail:
```sh
granular-audit
```
In a clone of a repo you can push to (Test branch and the tests in [DEVELOPING.md](DEVELOPING.md)):
```sh
granular-test-rw    # in your terminal
granular-test-ro    # in a Claude session
```

Git and `gh` now decide in their own process: a `claude` above them gets `ro`, anyone else gets `rw`.
- You gain: Claude's pushes fail and yours work, with nothing else running.
- You lose: no per-process flipping, and no record of who asked.

## Add the daemon

Type `granular-daemon` in a spare terminal tab and leave it running.

Git and `gh` now ask the daemon over `~/.granular/sock`, and only the daemon reads the Keychain for them. Every request prints the caller's chain on one line, outermost first, with a node number on each process that can carry a profile:
`login > zsh [3] > claude [2] > node > git > git-remote-https: ro`

- The daemon decides by the profile table (see Mechanism in [README.md](README.md)). The first process with a profile decides: a node you moved, else an app name (seeded for `claude` and `Claude.app`). With none the caller gets the default node (`rw`).
- Nodes 2 to 10 go to every matched process the daemon sees and to the outermost shell above it.
- Type a node number and Enter in the daemon's tab to move that node to the next profile. Enter alone lists the nodes with their pid and working directory. A process shows only after it has made a request or the scan has found a `claude` by name.
- Node 0 is `not under pid 1` and node 1 is `under pid 1`. Moving node 1 changes what a process with no node of its own gets.
- Type a new profile name (a letter, then letters, digits, `-` or `_`) and Enter to add it to the end of the cycle. Store its token with `granular-passwd <name> github.com`. A profile with no token answers `deny no item`.
- A node is freed when its process exits, and its number is reused.

- You gain: flip one Claude session to `rw` for a task and flip it back, and a line for every request.
- You lose: one more process to keep running. A Keychain dialog blocks the daemon until it is answered.

## The vault

The tokens live in a keychain file of their own, `~/Library/Keychains/granular.keychain-db`, with its own password.

The first `granular-passwd` run creates it, through a system dialog that asks for the password. The password stays out of this program.

- It relocks after a day and stays unlocked through sleep. Unlock it from any terminal: `security unlock-keychain ~/Library/Keychains/granular.keychain-db`
- Each login is an item: service `granular:<profile>:<host>`, account the username, secret the token. Git and `gh` share them.
- Rekey every item: `granular-passwd --rekey --all`. Rekey one item: `granular-passwd --rekey <profile> <host> [description]` reads the stored login, deletes the item and adds it again from the current build. Run it when a vault item prompts after a rebuild or a change of signing identity, because an item's access list names the build that stored it. It also changes the message with no token to paste: a given description replaces the old one, `""` clears it, and none keeps it.

- You gain: the tokens sit apart from the rest of your login keychain.
- You lose: a second password, and a locked vault gives no token until you unlock it.

## Audit

`granular-audit` asks: is this computer configured correctly? It changes nothing. A failure means the environment is wrong, not the program.

Steps:
1. Open your own terminal, not Claude.
2. If you use the daemon, start `granular-daemon` in another tab.
3. Run `granular-audit`.
4. For each failure the audit says what went wrong and prints the fix. Apply it, then run the audit again until nothing fails.

Some checks read the vault, so a prompt can appear (see What a prompt is). The script exits 1 if any check fails.

## Uninstall

Copy and paste each line.
```
# copy rw back to the system vault (asks for your vault password)
granular-passwd --export rw github.com | { read -r user && read -r pw && [ -n "$pw" ] && printf 'protocol=https\nhost=github.com\nusername=%s\npassword=%s\n\n' "$user" "$pw" | git credential-osxkeychain store; }

# stop the daemon (Ctrl-C in its tab), then remove everything
rm -rf ~/.granular
sudo rm /usr/local/bin/{granular,granular-git,granular-passwd,granular-daemon,gh,granular-audit,granular-test-ro,granular-test-rw}
git config --global --unset-all credential.helper
# git config --global --add credential.helper osxkeychain    # only if your Xcode git does not already have it
brew link gh    # then: gh auth login

# delete the vault. cannot be undone: the tokens are gone
# security delete-keychain ~/Library/Keychains/granular.keychain-db
```
Revoke the `ro` and `rw` tokens at https://github.com/settings/tokens
