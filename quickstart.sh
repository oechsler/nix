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

if [[ -t 1 ]]; then
  RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m'
  BLUE='\033[0;34m' BOLD='\033[1m' DIM='\033[2m' RESET='\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' BOLD='' DIM='' RESET=''
fi

info()    { echo -e "${BLUE}==>${RESET} ${BOLD}$*${RESET}"; }
success() { echo -e "    ${GREEN}✓${RESET} $*"; }
warn()    { echo -e "    ${YELLOW}!${RESET} $*"; }
error()   { echo -e "${RED}Error:${RESET} $*" >&2; exit 1; }

info "NixOS Quickstart"
echo ""

# Guard: must run on NixOS and as root before doing anything else
command -v nixos-version &>/dev/null || error "Not a NixOS system."

# Self-elevate when run as a file; error when piped (curl | bash needs sudo explicitly)
if [[ $EUID -ne 0 ]]; then
  if [[ -f "$0" ]]; then
    exec sudo "$0" "$@"
  else
    error "Must run as root. Use: curl -sL ... | sudo bash"
  fi
fi

REPO_URL="${REPO:-https://github.com/oechsler/nix.git}"
BRANCH="${BRANCH:-main}"
CLONE_DIR="/tmp/nix-config"
USER_HOME="$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)"

# Resolve the repo path from the running system's nixos-upgrade unit.
# The flake path is baked in as --flake /path/to/repo#hostname by install.sh.
# Falls back to asking the user if the unit is absent or disabled.
find_installed_repo() {
  local flake_dir
  flake_dir=$(systemctl show nixos-upgrade.service --property=ExecStart 2>/dev/null \
    | grep -o -- '--flake [^ ]*' | awk '{print $2}' | sed 's/#.*//' || true)
  if [[ -n "$flake_dir" && -f "$flake_dir/flake.nix" ]]; then
    echo "$flake_dir" && return
  fi

  # nixos-upgrade not configured — ask the user
  if [[ -t 0 ]]; then
    warn "Could not resolve repo path from nixos-upgrade.service."
    read -rp "Path to your NixOS config repo: " flake_dir
    flake_dir="${flake_dir/#\~/$USER_HOME}"
    [[ -f "$flake_dir/flake.nix" ]] && echo "$flake_dir" && return
  fi

  echo ""
}

INSTALLED_REPO="$(find_installed_repo)"
echo ""
# On an installed system: hand off to install.sh which handles the upgrade flow
if [[ -f "$INSTALLED_REPO/flake.nix" ]]; then
  success "Existing installation found at $INSTALLED_REPO"

  if [[ ! -t 0 ]]; then
    exec < /dev/tty || error "Cannot reopen terminal for interactive input."
  fi

  echo ""
  exec bash "$INSTALLED_REPO/install.sh" "$@"
fi

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
