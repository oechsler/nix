#!/usr/bin/env bash
set -euo pipefail

for command_name in find grep nix-shell mktemp cp mkdir chmod mv cat; do
  command -v "$command_name" >/dev/null || {
    printf 'ERROR: Required command not found: %s\n' "$command_name" >&2
    exit 1
  }
done

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CONFIG_DIR=$(dirname -- "$SCRIPT_DIR")
SSH_DIR="$HOME/.ssh"
AGE_DIR="$HOME/.config/sops/age"

die() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

echo "=== Import SSH Key for sops-nix ==="
echo ""

# 1. Find all SSH keys in ~/.ssh
[[ -d "$SSH_DIR" ]] || die "SSH directory not found: $SSH_DIR"

# Find all private SSH keys (files without .pub extension)
mapfile -t SSH_KEYS < <(
  find "$SSH_DIR" -maxdepth 1 -type f \
    ! -name '*.pub' ! -name 'known_hosts*' ! -name 'config' \
    ! -name 'authorized_keys*' -print 2>/dev/null |
    grep -E 'id_[a-z0-9]+$' || true
)

if [[ ${#SSH_KEYS[@]} -eq 0 ]]; then
  printf 'ERROR: No SSH keys found in %s\n' "$SSH_DIR" >&2
  echo ""
  echo "Please create an SSH key first:"
  echo "  ssh-keygen -t ed25519 -C \"your-email@example.com\""
  echo ""
  exit 1
fi

# 2. Select SSH key
SSH_KEY=""
if [[ ${#SSH_KEYS[@]} -eq 1 ]]; then
  SSH_KEY="${SSH_KEYS[0]}"
  echo "✓ Found SSH key: $SSH_KEY"
else
  echo "Found multiple SSH keys:"
  for i in "${!SSH_KEYS[@]}"; do
    echo "  [$i] ${SSH_KEYS[$i]}"
  done
  echo ""
  read -r -p "Select key number [0]: " KEY_NUM
  KEY_NUM=${KEY_NUM:-0}
  [[ "$KEY_NUM" =~ ^[0-9]+$ ]] || die "Invalid key number: $KEY_NUM"
  ((KEY_NUM < ${#SSH_KEYS[@]})) || die "Key number out of range: $KEY_NUM"
  SSH_KEY="${SSH_KEYS[$KEY_NUM]}"
  echo "✓ Selected: $SSH_KEY"
fi

# Check if public key exists
SSH_PUB_KEY="${SSH_KEY}.pub"
[[ -f "$SSH_PUB_KEY" ]] || die "Public key not found: $SSH_PUB_KEY"

# 3. Convert SSH key to age key
echo ""
echo "Converting SSH key to age key..."
mkdir -p -- "$AGE_DIR"
chmod 700 "$AGE_DIR"

# Convert public key
AGE_PUBLIC_KEY=$(nix-shell -p ssh-to-age --run "ssh-to-age < $(printf '%q' "$SSH_PUB_KEY")")
echo "✓ Age public key: $AGE_PUBLIC_KEY"

# Convert private key
AGE_PRIVATE_KEY=$(nix-shell -p ssh-to-age --run "ssh-to-age -private-key -i $(printf '%q' "$SSH_KEY")")
printf '%s\n' "$AGE_PRIVATE_KEY" >"$AGE_DIR/keys.txt"
chmod 600 "$AGE_DIR/keys.txt"
printf 'Age private key saved to %s\n' "$AGE_DIR/keys.txt"

# Also update system key (for sops-nix service)
SYSTEM_KEY_DIR="/persist/var/lib/sops/age"
if [ -d "/persist" ]; then
  for command_name in sudo tee; do
    command -v "$command_name" >/dev/null || die "Required command not found: $command_name"
  done
  sudo mkdir -p "$SYSTEM_KEY_DIR"
  echo "$AGE_PRIVATE_KEY" | sudo tee "$SYSTEM_KEY_DIR/keys.txt" >/dev/null
  sudo chmod 600 "$SYSTEM_KEY_DIR/keys.txt"
  echo "✓ Age private key saved to $SYSTEM_KEY_DIR/keys.txt"
fi

# 4. Update .sops.yaml
echo ""
echo "Updating .sops.yaml..."
USER_ALIAS="user_$(whoami)"
CONFIG_FILE="$CONFIG_DIR/.sops.yaml"
TEMP_CONFIG=$(mktemp "$CONFIG_DIR/.sops.yaml.XXXXXX")
trap 'rm -f "$TEMP_CONFIG"' EXIT

if [[ -f "$CONFIG_FILE" ]]; then
  cp -p "$CONFIG_FILE" "$CONFIG_FILE.bak"
  echo "✓ Existing .sops.yaml backed up to .sops.yaml.bak"
fi

cat >"$TEMP_CONFIG" <<EOF
keys:
  - &${USER_ALIAS} $AGE_PUBLIC_KEY

creation_rules:
  - path_regex: sops/sops.*\.yaml$
    key_groups:
      - age:
           - *${USER_ALIAS}
EOF
mv "$TEMP_CONFIG" "$CONFIG_FILE"
trap - EXIT
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
