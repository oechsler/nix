#!/usr/bin/env nix-shell
#!nix-shell -i bash -p sops

set -e
cd "$(dirname "$0")"

if [ ! -f sops.encrypted.yaml ]; then
    echo "ERROR: sops.encrypted.yaml not found"
    exit 1
fi

echo "Decrypting sops.encrypted.yaml → sops.decrypted.yaml"
sops -d sops.encrypted.yaml > sops.decrypted.yaml
echo "Done! Edit sops.decrypted.yaml, then run ./encrypt.sh"
