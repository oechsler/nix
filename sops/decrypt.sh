#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENCRYPTED_FILE="$SCRIPT_DIR/sops.encrypted.yaml"
DECRYPTED_FILE="$SCRIPT_DIR/sops.decrypted.yaml"

if [ ! -f "$ENCRYPTED_FILE" ]; then
    echo "❌ ERROR: Encrypted file not found: $ENCRYPTED_FILE"
    exit 1
fi

echo "Decrypting $ENCRYPTED_FILE → $DECRYPTED_FILE"
nix-shell -p sops --run "sops -d $ENCRYPTED_FILE > $DECRYPTED_FILE"
echo "✓ Decryption complete!"
echo ""
echo "Edit the file: $DECRYPTED_FILE"
echo "Then run: ./encrypt.sh"
