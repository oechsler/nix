#!/usr/bin/env bash
# NixOS Quickstart Bootstrap
#
# Downloads the NixOS configuration repository and runs the installer.
# Intended for use on a NixOS ISO (fresh install environment).
#
# Usage:
#   curl -sL https://raw.githubusercontent.com/oechsler/nix/main/quickstart.sh | bash
#
# Environment variables:
#   BRANCH  — Git branch to clone (default: main)
#   REPO    — Git repository URL (default: github.com/oechsler/nix)

set -euo pipefail

REPO_URL="${REPO:-https://github.com/oechsler/nix.git}"
BRANCH="${BRANCH:-main}"
CLONE_DIR="/tmp/nix-config"

# --- Colors ---
if [[ -t 1 ]]; then
  RED='\033[0;31m' GREEN='\033[0;32m' BLUE='\033[0;34m' BOLD='\033[1m' RESET='\033[0m'
else
  RED='' GREEN='' BLUE='' BOLD='' RESET=''
fi

info()  { echo -e "${BLUE}==>${RESET} ${BOLD}$*${RESET}"; }
error() { echo -e "${RED}ERROR:${RESET} $*" >&2; exit 1; }
ok()    { echo -e "    ${GREEN}$*${RESET}"; }

# --- Environment checks ---
info "NixOS Quickstart"
echo ""

[[ $EUID -eq 0 ]] || error "Must run as root. Try: sudo bash or log in as root on the NixOS ISO."

command -v nixos-version &>/dev/null || error "Not a NixOS system."

# Check network
if ! curl -sf --max-time 5 https://github.com > /dev/null 2>&1; then
  error "No network. Connect to the internet first (nmtui or iwctl)."
fi
ok "Network OK"

# --- Install git ---
if ! command -v git &>/dev/null; then
  info "Installing git..."
  nix-env -iA nixos.git
fi
ok "Git available"

# --- Clone repository ---
if [[ -d "$CLONE_DIR" ]]; then
  info "Updating existing clone at $CLONE_DIR..."
  git -C "$CLONE_DIR" fetch origin "$BRANCH"
  git -C "$CLONE_DIR" checkout "$BRANCH"
  git -C "$CLONE_DIR" reset --hard "origin/$BRANCH"
else
  info "Cloning $REPO_URL (branch: $BRANCH)..."
  git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$CLONE_DIR"
fi
ok "Repository ready at $CLONE_DIR"

# --- Hand off to installer ---
echo ""
info "Starting installer..."
echo ""
exec bash "$CLONE_DIR/install.sh" "$@"
