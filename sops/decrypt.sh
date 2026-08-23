#!/usr/bin/env nix-shell
#!nix-shell -i bash -p sops
# shellcheck shell=bash

set -e
cd "$(dirname "$0")"

if [ ! -f sops.encrypted.yaml ]; then
    echo "ERROR: sops.encrypted.yaml not found"
    exit 1
fi

echo "Decrypting sops.encrypted.yaml → sops.decrypted.yaml"
tmp_file=$(mktemp sops.decrypted.yaml.XXXXXX)
trap 'rm -f "$tmp_file"' EXIT
sops -d sops.encrypted.yaml > "$tmp_file"
mv "$tmp_file" sops.decrypted.yaml
echo "Done! Edit sops.decrypted.yaml, then run ./encrypt.sh"
