# Sourced by every story. Gives it a vault of fake tokens, a socket, and the steps.
# GRANULAR_BIN is the dev binary (bin/ci sets it). To run one story alone:
#   GRANULAR_BIN=build/dev/granular test/stories/02-profiles.sh

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$root" || exit 1
binary=${GRANULAR_BIN:-build/dev/granular}
export PATH="$(test/support/links "$binary"):$root:$PATH"

tmp=$(mktemp -d)
export GRANULAR_SOCKET=$tmp/sock
export GRANULAR_VAULT=$tmp/vault.keychain-db
tester=$root/test/support/level
export tester
failed=0
daemon=
lock=${TMPDIR:-/tmp}/granular-vault.lock

cleanup() {
  [ -n "$daemon" ] && { kill "$daemon" && wait "$daemon"; } 2>/dev/null
  security delete-keychain "$GRANULAR_VAULT" 2>/dev/null
  rmdir "$lock" 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT

# A keychain made with the security tool joins the user's search list, so one run at a time makes its vault
# and puts the list back.
make_vault() {
  until mkdir "$lock" 2>/dev/null; do sleep 0.1; done
  local searchlist
  searchlist=$(security list-keychains -d user | tr -d ' "')
  security create-keychain -p dev "$GRANULAR_VAULT" || exit 1
  security set-keychain-settings -t 3600 "$GRANULAR_VAULT"
  security unlock-keychain -p dev "$GRANULAR_VAULT"
  # shellcheck disable=SC2086
  security list-keychains -d user -s $searchlist
  rmdir "$lock"
  printf 'dev\nfake-ro-token\n' | granular-passwd --stdin ro dev.invalid || exit 1
  printf 'dev\nfake-rw-token\n' | granular-passwd --stdin rw dev.invalid || exit 1
}

step() {
  local desc=$1 out
  shift
  if out=$("$@" 2>&1); then
    echo "ok    $desc"
  else
    echo "FAIL  $desc"
    sed 's/^/        /' <<<"$out"
    failed=1
  fi
}

# The daemon reads its tab from a fifo, so a story can type into it with tab.
start_daemon() {
  mkfifo "$tmp/tab"
  exec 3<>"$tmp/tab"
  granular-daemon <&3 >/dev/null 2>"$tmp/daemon.log" &
  daemon=$!
  wait_for test -S "$GRANULAR_SOCKET"
  step "daemon starts" test -S "$GRANULAR_SOCKET"
}

tab() { echo "$1" >&3; sleep 0.3; }
wait_for() { for _ in $(seq 100); do "$@" && return 0; sleep 0.1; done; return 1; }
# The number the tab shows for pid, from the last listing in the daemon's log.
number_of() { grep "pid=$1 " "$tmp/daemon.log" | tail -1 | sed 's/^ *\([0-9]*\):.*/\1/'; }
finish() { exit "$failed"; }

make_vault
