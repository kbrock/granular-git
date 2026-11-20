#!/bin/bash
# With a daemon: who gets which token, and who may set a profile.
. "$(dirname "$0")/../support/story.sh"
start_daemon

step "a shell marked rw gets the rw token" sh -c 'granular-trust -1 rw >/dev/null && "$tester" --rw'
step "claude gets ro" test/support/claude "$tester" --ro
step "claude inside claude gets ro" test/support/claude test/support/claude "$tester" --ro
step "a shell marked ro gets the ro token" sh -c 'granular-trust -1 ro >/dev/null && "$tester" --ro'
step "trust rw is allowed under claude in dev" test/support/claude sh -c 'granular-trust -1 rw >/dev/null'
step "trust watch is allowed under claude" test/support/claude sh -c 'granular-trust -1 >/dev/null'
finish
