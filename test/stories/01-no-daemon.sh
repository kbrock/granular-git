#!/bin/bash
# With no daemon, a caller under claude gets ro from its own process, and git's own helper machinery takes the token.
. "$(dirname "$0")/../support/story.sh"

step "help prints" granular --help
step "ro under claude" test/support/claude "$tester" --ro
step "git credential fill under claude gets the ro token" test/support/claude sh -c 'test/support/fill | grep -q password=fake-ro-token'
finish
