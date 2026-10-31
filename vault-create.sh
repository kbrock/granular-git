#!/bin/bash
# Creates the keychain file that granular uses as its vault. Run it in your own terminal, because
# security asks for the new password on the tty. It never passes through this script.
# The file name must match VAULT in granular.rb, which names a file in ~/Library/Keychains.
# security also adds the new file to your keychain search list, which granular does not need.

path=${1:-$HOME/Library/Keychains/granular.keychain-db}

if [ -e "$path" ]; then
  echo "$path already exists"
  exit 1
fi
security create-keychain "$path" || exit 1
# Relock after a day, and not on sleep.
security set-keychain-settings -t 86400 "$path" || exit 1
security unlock-keychain "$path" || exit 1
echo "created $path"
echo "unlock it later with: security unlock-keychain $path"
echo "store logins with: granular-passwd ro github.com and granular-passwd rw github.com"
