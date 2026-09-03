#!/usr/bin/env nix-shell
#!nix-shell -i bash -p sops
# shellcheck shell=bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd -- "$script_dir"

if [[ ! -f sops.encrypted.yaml ]]; then
	printf 'ERROR: sops.encrypted.yaml not found\n' >&2
	exit 1
fi

printf 'Decrypting sops.encrypted.yaml -> sops.decrypted.yaml\n'
tmp_file=$(mktemp sops.decrypted.yaml.XXXXXX)
trap 'rm -f "$tmp_file"' EXIT
sops -d sops.encrypted.yaml >"$tmp_file"
mv "$tmp_file" sops.decrypted.yaml
printf 'Done! Edit sops.decrypted.yaml, then run ./encrypt.sh\n'
