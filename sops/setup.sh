#!/usr/bin/env bash
set -e

echo "=== Import SSH Key for sops-nix ==="
echo ""

# 1. Find all SSH keys in ~/.ssh
SSH_DIR="$HOME/.ssh"
if [ ! -d "$SSH_DIR" ]; then
    echo "❌ ERROR: SSH directory not found: $SSH_DIR"
    exit 1
fi

# Find all private SSH keys (files without .pub extension)
mapfile -t SSH_KEYS < <(find "$SSH_DIR" -maxdepth 1 -type f ! -name "*.pub" ! -name "known_hosts*" ! -name "config" ! -name "authorized_keys*" 2>/dev/null | grep -E "id_[a-z0-9]+$" || true)

if [ ${#SSH_KEYS[@]} -eq 0 ]; then
    echo "❌ ERROR: No SSH keys found in $SSH_DIR"
    echo ""
    echo "Please create an SSH key first:"
    echo "  ssh-keygen -t ed25519 -C \"your-email@example.com\""
    echo ""
    exit 1
fi

# 2. Select SSH key
SSH_KEY=""
if [ ${#SSH_KEYS[@]} -eq 1 ]; then
    SSH_KEY="${SSH_KEYS[0]}"
    echo "✓ Found SSH key: $SSH_KEY"
else
    echo "Found multiple SSH keys:"
    for i in "${!SSH_KEYS[@]}"; do
        echo "  [$i] ${SSH_KEYS[$i]}"
    done
    echo ""
    read -p "Select key number [0]: " KEY_NUM
    KEY_NUM=${KEY_NUM:-0}
    SSH_KEY="${SSH_KEYS[$KEY_NUM]}"
    echo "✓ Selected: $SSH_KEY"
fi

# Check if public key exists
SSH_PUB_KEY="${SSH_KEY}.pub"
if [ ! -f "$SSH_PUB_KEY" ]; then
    echo "❌ ERROR: Public key not found: $SSH_PUB_KEY"
    exit 1
fi

# 3. Convert SSH key to age key
echo ""
echo "Converting SSH key to age key..."
mkdir -p ~/.config/sops/age

# Convert public key
AGE_PUBLIC_KEY=$(nix-shell -p ssh-to-age --run "ssh-to-age < $SSH_PUB_KEY")
echo "✓ Age public key: $AGE_PUBLIC_KEY"

# Convert private key
AGE_PRIVATE_KEY=$(nix-shell -p ssh-to-age --run "ssh-to-age -private-key -i $SSH_KEY")
echo "$AGE_PRIVATE_KEY" > ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
echo "✓ Age private key saved to ~/.config/sops/age/keys.txt"

# Also update system key (for sops-nix service)
SYSTEM_KEY_DIR="/persist/var/lib/sops/age"
if [ -d "/persist" ]; then
    sudo mkdir -p "$SYSTEM_KEY_DIR"
    echo "$AGE_PRIVATE_KEY" | sudo tee "$SYSTEM_KEY_DIR/keys.txt" > /dev/null
    sudo chmod 600 "$SYSTEM_KEY_DIR/keys.txt"
    echo "✓ Age private key saved to $SYSTEM_KEY_DIR/keys.txt"
fi

# 4. Update .sops.yaml
echo ""
echo "Updating .sops.yaml..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")"
USER_ALIAS="user_$(whoami)"
cat > "$CONFIG_DIR/.sops.yaml" <<EOF
keys:
  - &${USER_ALIAS} $AGE_PUBLIC_KEY

creation_rules:
  - path_regex: sops/sops.*\.yaml$
    key_groups:
      - age:
          - *${USER_ALIAS}
EOF
echo "✓ .sops.yaml updated with user alias: $USER_ALIAS"

echo ""
echo "=== Setup complete! ==="
echo ""
echo "Helper scripts:"
echo "  cd sops/"
echo "  ./decrypt.sh  - Decrypt secrets for editing"
echo "  ./encrypt.sh  - Encrypt secrets after editing"
echo ""
echo "If you changed your SSH key, re-encrypt secrets:"
echo "  cd sops/"
echo "  sops updatekeys sops.encrypted.yaml"
echo ""