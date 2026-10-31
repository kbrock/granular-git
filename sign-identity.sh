#!/bin/bash
# This creates, once, the self-signed code-signing identity that `make` signs the binaries with.
# A stable identity keeps the Keychain's "Always Allow" across rebuilds; an ad-hoc signature prompts again.
# Run it in your own terminal: macOS asks for your login password to trust the certificate.
# Prints no secrets. The private key is a file only while this runs.

name=${1:-granular-signing}
login=$HOME/Library/Keychains/login.keychain-db

if security find-identity -v -p codesigning | grep -q "\"$name\""; then
  echo "$name already exists"
  exit 0
fi

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
pass=$(openssl rand -hex 16)

openssl req -x509 -newkey rsa:2048 -nodes -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -days 3650 \
  -subj "/CN=$name" -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null || exit 1
openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -out "$tmp/id.p12" -passout "pass:$pass" || exit 1
security import "$tmp/id.p12" -k "$login" -P "$pass" -T /usr/bin/codesign || exit 1
# codesign ignores an identity that is not trusted for code signing.
security add-trusted-cert -r trustRoot -p codeSign -k "$login" "$tmp/cert.pem" || exit 1
echo "created $name"
