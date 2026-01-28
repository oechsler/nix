#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENCRYPTED_FILE="$SCRIPT_DIR/sops.encrypted.yaml"
DECRYPTED_FILE="$SCRIPT_DIR/sops.decrypted.yaml"

if [ ! -f "$DECRYPTED_FILE" ]; then
    echo "❌ ERROR: Decrypted file not found: $DECRYPTED_FILE"
    echo ""
    echo "Run ./decrypt.sh first to create the decrypted file."
    exit 1
fi

echo "Encrypting $DECRYPTED_FILE → $ENCRYPTED_FILE"
nix-shell -p sops --run "sops -e $DECRYPTED_FILE > $ENCRYPTED_FILE"
echo "✓ Encryption complete!"
echo ""
echo "You can now commit $ENCRYPTED_FILE to git."
