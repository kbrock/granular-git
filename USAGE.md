# Usage

Each program, once it is installed ([INSTALL.md](INSTALL.md)). The idea behind them is in [README.md](README.md).

## granular-daemon

Run `granular-daemon` in a spare terminal tab and leave it running. Git and `gh` then ask it over `~/.granular/sock`, and it is the only program that reads the vault for them.

**The request line.** Every request prints the caller's chain on one line, outermost first:
```
rex > login [8] rw > bash > git > git > git-remote-http
```
- A process that carries a slot shows its slot number in brackets.
- The process that decided shows the profile after its name.
- When no rule matched, the line leads with `root [0]` and its profile.

**The tab.** The daemon reads what you type in its tab:
- Enter alone lists the table: the rules, then the running processes that hold a slot, each with its profile and working directory.
- A slot number and Enter moves that entry to the next profile in the cycle (`ro`, `rw`, then any you added). A rule entry changes every process that matches the rule. A process entry changes that process and everything under it.
- A new profile name (a letter, then letters, digits, `-` or `_`) and Enter adds it to the end of the cycle. Store its token with `granular-passwd <name> github.com`.

**Slots.** A process gets a slot when it decides a request, and when it is the outermost shell above a request that no rule decided. Running `claude` processes get one when you list the table. A slot frees when its process exits, and the number is reused.

**Named shells.** To give read-write only to shells you name, move the `login` and `sshd-session` entries to `ro`, then move your own shells' entries to `rw`.

**Things to know.**
- The table lives in the daemon's memory. A restart returns it to the starting rules.
- A Keychain dialog blocks the daemon until you answer it.
- With no daemon, git and `gh` decide in their own process and apply the starting rules. No request line, no slots.

## granular-trust

Prints the processes above you: the distance up, the name and the pid. It reads no profile and does not contact the daemon.
```
-3  login  50249
-2  bash  50250
-1  bash  61139
0  granular  61140
```
Use it to find the pid of the shell you want, or to see where a process sits in a chain.

## granular-passwd

Stores and moves the tokens. Run it in your own terminal. It refuses when the caller's profile is anything but read-write, so Claude cannot run it.

| Command | Does |
|---|---|
| `granular-passwd <profile> <host> [message]` | Asks for the username and the token, and stores them. |
| `granular-passwd --stdin <profile> <host> [message]` | Reads the username and the token as two lines on stdin. |
| `granular-passwd --rekey <profile> <host> [message]` | Stores the item again from the current build. Without a message the old one stays, and `""` clears it. |
| `granular-passwd --rekey --all` | Rekeys every item in the vault. |
| `granular-passwd --export <profile> <host>` | Writes the username and the token as two lines, to a pipe only. |

The message is printed on stderr whenever that profile is served a token. Add `-v` for a confirmation line after a store.

## granular-git

Git runs it as the credential helper. Only `get` does anything. `store` and `erase` do nothing, so a token typed at a git prompt is lost. Add or change a token with `granular-passwd`.

A host with no item under the caller's profile prints `granular: no token for <host> profile <name>`, and git falls through to its own prompt.

## gh

The wrapper runs the real `gh` with the caller's token in `GH_TOKEN`.
- `gh auth token` is refused with the profile's message.
- `gh auth status` runs with the token, which `gh` shows masked. An extra argument runs it without the token.
- Any other `gh auth` command runs without the token.

## granular-audit

Run it in your own terminal. It changes nothing. It checks the machine under these headings: `granular-git`, `credential.helper`, `granular-daemon`, `vault`, `stored credentials` and `gh`.
- `PASS` lines hold. `FAIL` lines say what is wrong and print the command that fixes it.
- `INFO` lines list the vault's items. `NOTE` marks something worth knowing that is not a failure.
- It exits 1 if any check failed. Apply the fixes and run it again until none fail.

Some checks read the vault, so a Keychain prompt can appear.
