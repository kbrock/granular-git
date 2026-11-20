#!/bin/bash
# Two marked sessions: each has its own number, flipping one leaves the other, and an exited session leaves the tab.
. "$(dirname "$0")/../support/story.sh"
start_daemon

# A session is a shell that marks itself ro, waits for the go file, then reports its level.
session() {
  sh -c 'echo $$ > "$1/$2.pid"; granular-trust -1 ro >/dev/null; touch "$1/$2.ready"
    while [ ! -e "$1/go" ]; do sleep 0.1; done
    "$tester" | sed -n "s/^level: //p" > "$1/$2.level"' sh "$tmp" "$1" &
}
session a
session b
wait_for test -e "$tmp/a.ready"
wait_for test -e "$tmp/b.ready"
tab ""
a_pid=$(cat "$tmp/a.pid" 2>/dev/null)
b_pid=$(cat "$tmp/b.pid" 2>/dev/null)
a_num=$(number_of "$a_pid")
b_num=$(number_of "$b_pid")
tab "$a_num"
touch "$tmp/go"
wait_for test -s "$tmp/a.level"
wait_for test -s "$tmp/b.level"
sleep 1
mark=$(wc -l <"$tmp/daemon.log")
tab ""

both_listed() { echo "a=$a_num b=$b_num"; [ -n "$a_num" ] && [ -n "$b_num" ] && [ "$a_num" != "$b_num" ]; }
flip_only_one() { echo "a=$(cat "$tmp/a.level") b=$(cat "$tmp/b.level")"; [ "$(cat "$tmp/a.level")" = rw ] && [ "$(cat "$tmp/b.level")" = ro ]; }
chain_numbers() { grep -q "sh \[$a_num\] rw" "$tmp/daemon.log" && grep -q "sh \[$b_num\] ro" "$tmp/daemon.log"; }
entries_freed() { ! tail -n +"$((mark + 1))" "$tmp/daemon.log" | grep -q "pid=$a_pid \|pid=$b_pid "; }
step "each session has its own number" both_listed
step "flipping one session leaves the other" flip_only_one
step "the chain line shows the session number" chain_numbers
step "exited sessions leave the tab" entries_freed
finish
