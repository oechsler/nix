#!/usr/bin/env nix-shell
#!nix-shell -i bash -p sops
# shellcheck shell=bash

set -e
cd "$(dirname "$0")"

if [ ! -f sops.decrypted.yaml ]; then
    echo "ERROR: sops.decrypted.yaml not found. Run ./decrypt.sh first."
    exit 1
fi

echo "Encrypting sops.decrypted.yaml → sops.encrypted.yaml"
tmp_file=$(mktemp sops.encrypted.yaml.XXXXXX)
trap 'rm -f "$tmp_file"' EXIT
sops -e sops.decrypted.yaml > "$tmp_file"
mv "$tmp_file" sops.encrypted.yaml
echo "Done! You can now commit sops.encrypted.yaml"
