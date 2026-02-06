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
nixos-install --flake "$REPO_DIR#$HOST"

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
  read -rp "Username to set password for: " USERNAME
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

SOPS_DIR="/mnt/home/$USERNAME/.config/sops/age"
mkdir -p "$SOPS_DIR"
echo "$AGE_KEY" > "$SOPS_DIR/keys.txt"
chmod 600 "$SOPS_DIR/keys.txt"
echo "==> Age key saved to $SOPS_DIR/keys.txt"

if [[ ! -d "/mnt/home/$USERNAME/repos/nix" ]]; then
  echo "==> Copying config to ~/repos/nix..."
  mkdir -p "/mnt/home/$USERNAME/repos"
  cp -r "$REPO_DIR" "/mnt/home/$USERNAME/repos/nix"
  nixos-enter --root /mnt -c "chown -R $USERNAME:users /home/$USERNAME/repos"
fi

if [[ -n "$PASSWORD" ]]; then
  echo "==> Setting password for '$USERNAME'..."
  nixos-enter --root /mnt -c "echo '$USERNAME:$PASSWORD' | chpasswd"
else
  echo "==> Setting password for '$USERNAME'..."
  nixos-enter --root /mnt -c "passwd $USERNAME"
fi

echo "==> Installation complete. You can reboot now."
