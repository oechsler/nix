#!/usr/bin/env bash
set -euo pipefail

HOST=""
USERNAME=""
SSH_KEY=""
YES=false
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

list_hosts() {
  echo "Available hosts:"
  for dir in "$SCRIPT_DIR"/hosts/*/; do
    echo "  $(basename "$dir")"
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--host) HOST="$2"; shift 2 ;;
    -u|--user) USERNAME="$2"; shift 2 ;;
    -s|--ssh-key) SSH_KEY="$2"; shift 2 ;;
    -y|--yes) YES=true; shift ;;
    *)
      echo "Usage: $0 -h <hostname> [-u <username>] [-s <ssh-key>] [-y]"
      list_hosts
      exit 1
      ;;
  esac
done

if [[ -z "$HOST" ]]; then
  echo "Usage: $0 -h <hostname> [-u <username>] [-s <ssh-key>] [-y]"
  list_hosts
  exit 1
fi

REPO_DIR="$SCRIPT_DIR"
HOST_DIR="$REPO_DIR/hosts/$HOST"

if [[ ! -d "$HOST_DIR" ]]; then
  echo "Error: host '$HOST' not found in $REPO_DIR/hosts/"
  exit 1
fi

export NIX_CONFIG="experimental-features = nix-command flakes"

# LUKS password setup
if [[ ! -f /tmp/luks-password ]]; then
  echo ""
  echo "==> Setting up LUKS disk encryption..."
  read -rsp "Enter LUKS password: " LUKS_PASS
  echo
  read -rsp "Confirm LUKS password: " LUKS_PASS_CONFIRM
  echo
  if [[ "$LUKS_PASS" != "$LUKS_PASS_CONFIRM" ]]; then
    echo "Error: Passwords do not match"
    exit 1
  fi
  echo "$LUKS_PASS" > /tmp/luks-password
  chmod 600 /tmp/luks-password
  echo "    LUKS password saved to /tmp/luks-password"
else
  echo "==> Using existing /tmp/luks-password"
fi

echo "==> Detecting NixOS version for stateVersion..."
NIXOS_VERSION="$(nixos-version | cut -d. -f1,2)"
echo "    Detected version: $NIXOS_VERSION"
sed -i "s|system\.stateVersion = \"[^\"]*\"|system.stateVersion = \"$NIXOS_VERSION\"|" "$HOST_DIR/configuration.nix"
sed -i "s|home\.stateVersion = \"[^\"]*\"|home.stateVersion = \"$NIXOS_VERSION\"|" "$HOST_DIR/home.nix"
git -C "$REPO_DIR" add "$HOST_DIR/configuration.nix" "$HOST_DIR/home.nix"

DISKO_ARGS=(--mode destroy,format,mount --flake "$REPO_DIR#$HOST")
if [[ "$YES" == true ]]; then
  DISKO_ARGS+=(--yes-wipe-all-disks)
fi

echo "==> Partitioning and formatting disks..."
nix run github:nix-community/disko -- "${DISKO_ARGS[@]}"

echo "==> Generating hardware configuration..."
nixos-generate-config --root /mnt --show-hardware-config > "$HOST_DIR/hardware-configuration.generated.nix"
git -C "$REPO_DIR" add --all

echo "==> Installing NixOS..."
nixos-install --flake "$REPO_DIR#$HOST" --no-root-password

echo "==> Setting up SSH key and sops age key..."
if [[ -n "$SSH_KEY" ]]; then
  SSH_KEY_FILE="$SSH_KEY"
  AGE_KEY="$(nix-shell -p ssh-to-age --run "ssh-to-age -private-key -i $SSH_KEY_FILE")"
else
  echo "Paste your ed25519 private SSH key (end with Ctrl+D):"
  SSH_KEY_FILE="$(mktemp)"
  cat > "$SSH_KEY_FILE"
  chmod 600 "$SSH_KEY_FILE"
  AGE_KEY="$(nix-shell -p ssh-to-age --run "ssh-to-age -private-key -i $SSH_KEY_FILE")"
fi

if [[ -z "$USERNAME" ]]; then
  read -rp "Username for SSH/sops setup: " USERNAME
fi

SSH_DIR="/mnt/home/$USERNAME/.ssh"
mkdir -p "$SSH_DIR"
cp "$SSH_KEY_FILE" "$SSH_DIR/id_ed25519"
ssh-keygen -y -f "$SSH_KEY_FILE" > "$SSH_DIR/id_ed25519.pub"
chmod 700 "$SSH_DIR"
chmod 600 "$SSH_DIR/id_ed25519"
chmod 644 "$SSH_DIR/id_ed25519.pub"
echo "==> SSH key pair saved to $SSH_DIR/"

# Clean up temp file if interactive
[[ -z "$SSH_KEY" ]] && rm -f "$SSH_KEY_FILE"

SOPS_USER_DIR="/mnt/home/$USERNAME/.config/sops/age"
SOPS_SYSTEM_DIR="/mnt/persist/var/lib/sops/age"
mkdir -p "$SOPS_USER_DIR" "$SOPS_SYSTEM_DIR"
echo "$AGE_KEY" > "$SOPS_USER_DIR/keys.txt"
echo "$AGE_KEY" > "$SOPS_SYSTEM_DIR/keys.txt"
chmod 600 "$SOPS_USER_DIR/keys.txt" "$SOPS_SYSTEM_DIR/keys.txt"
echo "==> Age key saved to $SOPS_USER_DIR/ and $SOPS_SYSTEM_DIR/"

if [[ ! -d "/mnt/home/$USERNAME/repos/nix" ]]; then
  echo "==> Copying config to ~/repos/nix..."
  mkdir -p "/mnt/home/$USERNAME/repos"
  cp -r "$REPO_DIR" "/mnt/home/$USERNAME/repos/nix"
fi

echo "==> Fixing home directory ownership..."
nixos-enter --root /mnt -c "chown -R $USERNAME:users /home/$USERNAME"

# Cleanup
rm -f /tmp/luks-password

echo ""
echo "==> Installation complete!"
echo "    - LUKS: Enter disk encryption password at boot"
echo "    - Login: Password is set declaratively in NixOS config"
echo ""
echo "You can reboot now."
