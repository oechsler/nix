#!/usr/bin/env nix-shell
#!nix-shell -i bash -p age gzip gnutar
# shellcheck shell=bash

set -euo pipefail
cd "$(dirname "$0")"

AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
[ -f "$AGE_KEY_FILE" ] || {
  echo "Error: Age identity not found: $AGE_KEY_FILE" >&2
  exit 1
}

mkdir -p files
age -d -i "$AGE_KEY_FILE" blob.tar.gz.age \
  | gzip -d \
  | tar xf - -C files

echo "Decrypted blob.tar.gz.age to ./files/"
