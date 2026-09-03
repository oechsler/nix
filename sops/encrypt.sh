#!/usr/bin/env nix-shell
#!nix-shell -i bash -p sops
# shellcheck shell=bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd -- "$script_dir"

if [[ ! -f sops.decrypted.yaml ]]; then
  printf 'ERROR: sops.decrypted.yaml not found. Run ./decrypt.sh first.\n' >&2
  exit 1
fi

printf 'Encrypting sops.decrypted.yaml -> sops.encrypted.yaml\n'
tmp_file=$(mktemp sops.encrypted.yaml.XXXXXX)
trap 'rm -f "$tmp_file"' EXIT
sops -e sops.decrypted.yaml >"$tmp_file"
mv "$tmp_file" sops.encrypted.yaml
printf 'Done! You can now commit sops.encrypted.yaml\n'
