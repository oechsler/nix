#!/usr/bin/env nix-shell
#!nix-shell -i bash -p age gzip gnutar
# shellcheck shell=bash

set -euo pipefail
cd "$(dirname "$0")"

if [ ! -d files ] || [ -z "$(ls -A files)" ]; then
  echo "Error: ./files/ is empty or does not exist"
  exit 1
fi

AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
[ -f "$AGE_KEY_FILE" ] || {
  echo "Error: Age identity not found: $AGE_KEY_FILE" >&2
  exit 1
}

RECIPIENT=$(age-keygen -y "$AGE_KEY_FILE")
tar cf - -C files . \
  | gzip \
  | age -r "$RECIPIENT" -o blob.tar.gz.age

echo "Encrypted ./files/ to blob.tar.gz.age using the configured Age identity"
