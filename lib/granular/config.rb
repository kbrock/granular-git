VERSION = "0.2.0"
SELF_PREFIX = "granular-"
# A login is a Keychain item: service "granular:<profile>:<host>", account = username, secret = token.
KEYCHAIN_PREFIX = "granular:"
MAX_DEPTH = 64
APPLETS = ["git", "passwd", "daemon", "trust", "gh"]
SHELLS = ["sh", "bash", "zsh", "fish", "dash", "ksh", "tcsh"]
# The table of nodes. A node matches a process by its pid, if it has one, and by its name, if it has one. A
# name starting with "/" is an executable path; any other name is a file name. The walk takes the caller,
# then its parents. For each process the first matching node with a profile, from the bottom of the table
# up, decides. Node 0 has pid 0, the parent of launchd, so the walk reaches it last. The nodes after the
# rules are slots, added as processes are claimed.
MAX_NODES = 32
# git and gh ask granular-daemon. true: with no daemon they give no token. false: they decide in their own process.
REQUIRE_DAEMON = false
# The keychain file in ~/Library/Keychains that holds the logins.
VAULT = "granular.keychain-db"
# The gh that the wrapper runs. `brew unlink gh` leaves it here and takes it off PATH.
REAL_GH = "/opt/homebrew/opt/gh/bin/gh"
