#!/bin/bash
# Reproduces a claude whose executable was replaced. Run it from inside a repo with an https origin.
# It starts a copy of Homebrew's bash named claude, deletes the copy, and has that process run git every
# 5 seconds for 2 minutes. Watch granular-daemon's tab: the process has no readable path.
# (Apple's /bin/bash is a platform binary and is killed when copied, so it uses Homebrew's.)
dir=$(mktemp -d)
cp /opt/homebrew/bin/bash "$dir/claude" || exit 1
"$dir/claude" -c 'for i in $(seq 24); do git push --dry-run >/dev/null 2>&1; sleep 5; done' &
pid=$!
sleep 1
rm "$dir/claude"
rmdir "$dir"
echo "pid $pid is running with its executable deleted"
