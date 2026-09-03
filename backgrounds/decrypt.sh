#!/usr/bin/env nix-shell
#!nix-shell -i bash -p age gzip gnutar
# shellcheck shell=bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd -- "$script_dir"

AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
[[ -f "$AGE_KEY_FILE" ]] || {
  printf 'Error: Age identity not found: %s\n' "$AGE_KEY_FILE" >&2
  exit 1
}

mkdir -p -- files
age -d -i "$AGE_KEY_FILE" blob.tar.gz.age |
  gzip -d |
  tar xf - -C files

printf 'Decrypted blob.tar.gz.age to ./files/\n'
