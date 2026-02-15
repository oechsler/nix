#!/usr/bin/env nix-shell
#!nix-shell -i bash -p sops

set -e
cd "$(dirname "$0")"

if [ ! -f sops.decrypted.yaml ]; then
    echo "ERROR: sops.decrypted.yaml not found. Run ./decrypt.sh first."
    exit 1
fi

echo "Encrypting sops.decrypted.yaml → sops.encrypted.yaml"
sops -e sops.decrypted.yaml > sops.encrypted.yaml
echo "Done! You can now commit sops.encrypted.yaml"
