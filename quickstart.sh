#!/usr/bin/env bash
# NixOS Quickstart Bootstrap
#
# Downloads the NixOS configuration repository and runs the installer.
# Intended for use on a NixOS ISO (fresh install environment).
#
# Usage (on NixOS ISO):
#   curl -sL https://raw.githubusercontent.com/oechsler/nix/main/quickstart.sh | sudo bash
#   curl -sL https://raw.githubusercontent.com/oechsler/nix/main/quickstart.sh | sudo bash -s -- [FLAGS]
#
# Environment variables:
#   BRANCH  — Git branch to clone (default: main)
#   REPO    — Git repository URL (default: github.com/oechsler/nix)
{
set -euo pipefail

REPO_URL="${REPO:-https://github.com/oechsler/nix.git}"
BRANCH="${BRANCH:-main}"
CLONE_DIR="/tmp/nix-config"

if [[ -t 1 ]]; then
  RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m'
  BLUE='\033[0;34m' BOLD='\033[1m' RESET='\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' BOLD='' RESET=''
fi

info()    { echo -e "${BLUE}==>${RESET} ${BOLD}$*${RESET}"; }
success() { echo -e "    ${GREEN}$*${RESET}"; }
warn()    { echo -e "${YELLOW}!!${RESET} $*"; }
error()   { echo -e "${RED}ERROR:${RESET} $*" >&2; exit 1; }

info "NixOS Quickstart"
echo ""

[[ $EUID -eq 0 ]] || error "Must run as root. Log in as root on the NixOS ISO."
command -v nixos-version &>/dev/null || error "Not a NixOS system."

if ! curl -sf --max-time 5 https://github.com > /dev/null 2>&1; then
  error "No network. Connect to the internet first (nmtui or iwctl)."
fi
success "Network OK"

if ! command -v git &>/dev/null; then
  info "Installing git..."
  echo ""
  nix-env -iA nixos.git
fi
success "Git available"

echo ""
if [[ -d "$CLONE_DIR" ]]; then
  info "Updating existing clone..."
  echo ""
  git -C "$CLONE_DIR" fetch origin "$BRANCH"
  git -C "$CLONE_DIR" checkout "$BRANCH"
  git -C "$CLONE_DIR" reset --hard "origin/$BRANCH"
else
  info "Cloning repository (branch: $BRANCH)..."
  echo ""
  git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$CLONE_DIR"
fi
success "Repository ready"

# When piped (curl | bash), stdin is at EOF after the { } block is read.
# Reopen from /dev/tty so the installer can prompt interactively.
if [[ ! -t 0 ]]; then
  exec < /dev/tty || error "Cannot reopen terminal for interactive input."
fi

echo ""
info "Starting installer..."
echo ""
exec bash "$CLONE_DIR/install.sh" "$@"
exit
}
