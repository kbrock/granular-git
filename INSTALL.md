# Install

## What a prompt is

A prompt is the macOS dialog that appears when a program asks to read a Keychain item. granular triggers one the first time it reads each token, and again when the signing identity changes.

It reads: "granular wants to use your confidential information stored in 'granular:ro:github.com' in your keychain", and asks for a keychain password.
- Allow: this read only. It asks again next time.
- Always Allow: remembered for every build signed by the same Team ID.
- Deny: refuses the read.

What to press:
- Allow or Always Allow a prompt that names `granular` and `granular:ro:github.com` or `granular:rw:github.com`.
- Deny a prompt that names anything else, such as `security` or `nc`. Something else is asking for a token.

A prompt appears once per Team ID per item (`ro` and `rw` are two items). A rebuild signed with the same Team ID keeps the approval. A different Team ID, such as another Apple ID, brings the prompts back until you run `granular-passwd --rekey --all`.

## Signing certificate

Once, on the computer that builds. `make` signs with an Apple Development certificate. A free Apple ID is enough. The certificate carries your Team ID, which is what lets macOS remember Always Allow across rebuilds.

1. In Xcode: Settings, Accounts, add your Apple ID.
2. Select the account, click Manage Certificates, click **+**, choose Apple Development.
3. Check that it signs:
   ```sh
   security find-identity -v -p codesigning    # lists "Apple Development: you@example.com (ID)"
   ```
4. The first build asks to let `codesign` use the key. Choose Always Allow.

If step 3 lists nothing, but `security find-identity -p codesigning` (without `-v`) lists the certificate, Apple's intermediate certificate is missing from your keychain:
```sh
curl -fsS -o /tmp/AppleWWDRCAG3.cer https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer
openssl x509 -inform DER -in /tmp/AppleWWDRCAG3.cer -noout -fingerprint -sha1
# import only if it prints 06:EC:06:59:9F:4E:D0:02:7C:C5:89:56:B4:D3:AC:12:55:11:4F:35
security import /tmp/AppleWWDRCAG3.cer -k ~/Library/Keychains/login.keychain-db
```

The certificate expires one year after you create it. When it does, `make` stops with "no valid Apple Development identity". Create a new one with the same steps. The requirement names the Team ID, not the certificate, so a certificate from the same Apple ID keeps working with no rekey. If the Team ID ever changes, run `granular-passwd --rekey --all`.

## Basic mode, no daemon

In your own terminal. On the computer with Spinel:
```sh
make dist    # builds dist/granular-<tag>[+commits].tgz and its .sha256
```
`make` signs with the certificate from [Signing certificate](#signing-certificate).

On the computer you are setting up:
```sh
cd ~/Downloads
scp 'host:src/granular-git/dist/granular-*' .
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

Install the new tarball as above and restart the daemon. A build signed with the same identity keeps its approvals. If the vault prompts again (a build signed with a different identity), rekey the items:
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
granular-test --rw    # in your terminal
granular-test --ro    # in a Claude session
```

Git and `gh` now decide in their own process by the starting rules: `claude` gets the read-only token, and your terminal and ssh sessions get the read-write token.
- You gain: Claude's pushes fail and yours work, with nothing else running.
- You lose: no per-process flipping, and no record of who asked.

## Add the daemon

Type `granular-daemon` in a spare terminal tab and leave it running.

Git and `gh` now ask the daemon over `~/.granular/sock`, and only the daemon reads the Keychain for them. Every request prints the caller's chain on one line:
`rex > login [8] rw > bash > claude [3] ro > node > git > git-remote-http`

The deciding process shows its profile. Type a slot number and Enter in the daemon's tab to move it to the next profile, and Enter alone to list the table. [USAGE.md](USAGE.md) covers the tab, the slots and how to give read-write to named shells only.

- You gain: flip one Claude session to `rw` for a task and flip it back, and a line for every request.
- You lose: one more process to keep running. A Keychain dialog blocks the daemon until it is answered.

## The vault

The tokens live in a keychain file of their own, `~/Library/Keychains/granular.keychain-db`, with its own password.

The first `granular-passwd` run creates it, through a system dialog that asks for the password. The password stays out of this program.

- It relocks after a day and stays unlocked through sleep. Unlock it from any terminal: `security unlock-keychain ~/Library/Keychains/granular.keychain-db`
- Each login is an item: service `granular:<profile>:<host>`, account the username, secret the token. Git and `gh` share them.
- Any host works: `granular-git` serves a host when the vault holds an item for it under the caller's profile, such as `granular-passwd rw gitlab.com`. A host with no item gets no token. The `gh` wrapper covers github.com only.
- Rekey every item: `granular-passwd --rekey --all` rekeys each `granular:*` item in the vault. Rekey one item: `granular-passwd --rekey <profile> <host> [description]` reads the stored login, deletes the item and adds it again from the current build. Run it when a vault item prompts after a change of signing identity, because an item's access list names the identity that stored it. It also changes the message with no token to paste: a given description replaces the old one, `""` clears it, and none keeps it.
- `granular-git` never saves. Git's `store` and `erase` calls do nothing, so a token typed at a git prompt is lost. Add or change a token with `granular-passwd <profile> github.com`.

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
sudo rm /usr/local/bin/{granular,granular-git,granular-passwd,granular-daemon,granular-trust,gh,granular-audit,granular-test}
git config --global --unset-all credential.helper
# git config --global --add credential.helper osxkeychain    # only if your Xcode git does not already have it
brew link gh    # then: gh auth login

# delete the vault. cannot be undone: the tokens are gone
# security delete-keychain ~/Library/Keychains/granular.keychain-db
```
Revoke the `ro` and `rw` tokens at https://github.com/settings/tokens
