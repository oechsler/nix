#!/usr/bin/env bash
set -euo pipefail

HOST=""
USERNAME=""
PASSWORD=""
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
    -p|--password) PASSWORD="$2"; shift 2 ;;
    -s|--ssh-key) SSH_KEY="$2"; shift 2 ;;
    -y|--yes) YES=true; shift ;;
    *)
      echo "Usage: $0 -h <hostname> [-u <username>] [-p <password>] [-s <ssh-key>] [-y]"
      list_hosts
      exit 1
      ;;
  esac
done

if [[ -z "$HOST" ]]; then
  echo "Usage: $0 -h <hostname> [-u <username>] [-p <password>] [-s <ssh-key>] [-y]"
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

if [[ "$YES" != true ]]; then
  echo "This will erase all disks configured for '$HOST'."
  read -rp "Continue? [y/N] " confirm
  [[ "$confirm" == [yY] ]] || exit 1
fi

echo "==> Partitioning and formatting disks..."
nix run github:nix-community/disko -- --mode destroy,format,mount --flake "$REPO_DIR#$HOST"

echo "==> Generating hardware configuration..."
nixos-generate-config --root /mnt --show-hardware-config > "$HOST_DIR/hardware-configuration.nix"
# Remove fileSystems and swapDevices (disko handles mounts)
sed -i '/^\s*fileSystems\./,/};/d' "$HOST_DIR/hardware-configuration.nix"
sed -i '/^\s*swapDevices\s*=/,/];/d' "$HOST_DIR/hardware-configuration.nix"

echo "==> Installing NixOS..."
nixos-install --flake "$REPO_DIR#$HOST"

echo "==> Setting up sops age key..."
if [[ -n "$SSH_KEY" ]]; then
  # Non-interactive: derive age key from provided SSH key
  AGE_KEY="$(nix-shell -p ssh-to-age --run "ssh-to-age -private-key -i $SSH_KEY")"
else
  # Interactive: paste the private SSH key
  echo "Paste your ed25519 private SSH key (end with Ctrl+D):"
  SSH_TMP="$(mktemp)"
  cat > "$SSH_TMP"
  chmod 600 "$SSH_TMP"
  AGE_KEY="$(nix-shell -p ssh-to-age --run "ssh-to-age -private-key -i $SSH_TMP")"
  rm -f "$SSH_TMP"
fi

if [[ -z "$USERNAME" ]]; then
  read -rp "Username to set password for: " USERNAME
fi

SOPS_DIR="/mnt/home/$USERNAME/.config/sops/age"
mkdir -p "$SOPS_DIR"
echo "$AGE_KEY" > "$SOPS_DIR/keys.txt"
chmod 600 "$SOPS_DIR/keys.txt"
echo "==> Age key saved to $SOPS_DIR/keys.txt"

if [[ -n "$PASSWORD" ]]; then
  echo "==> Setting password for '$USERNAME'..."
  nixos-enter --root /mnt -c "echo '$USERNAME:$PASSWORD' | chpasswd"
else
  echo "==> Setting password for '$USERNAME'..."
  nixos-enter --root /mnt -c "passwd $USERNAME"
fi

echo "==> Installation complete. You can reboot now."
