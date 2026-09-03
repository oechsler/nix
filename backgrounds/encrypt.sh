#!/usr/bin/env nix-shell
#!nix-shell -i bash -p age gzip gnutar
# shellcheck shell=bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd -- "$script_dir"

shopt -s nullglob dotglob
files=(files/*)
if [[ ! -d files ]] || [[ ${#files[@]} -eq 0 ]]; then
	printf 'Error: ./files/ is empty or does not exist\n' >&2
	exit 1
fi

AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
[[ -f "$AGE_KEY_FILE" ]] || {
	printf 'Error: Age identity not found: %s\n' "$AGE_KEY_FILE" >&2
	exit 1
}

RECIPIENT=$(age-keygen -y "$AGE_KEY_FILE")
[[ -n "$RECIPIENT" ]] || {
	printf 'Error: Could not derive an Age recipient from %s\n' "$AGE_KEY_FILE" >&2
	exit 1
}
tar cf - -C files . |
	gzip |
	age -r "$RECIPIENT" -o blob.tar.gz.age

printf 'Encrypted ./files/ to blob.tar.gz.age using the configured Age identity\n'
