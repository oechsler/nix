#!/usr/bin/env bash
# NixOS Interactive Installer
#
# Smart-hybrid installer that reads the host's configuration to determine
# which features are enabled, and only prompts for relevant setup steps.
#
# Usage:
#   ./install.sh                      # Interactive (recommended)
#   ./install.sh -h HOST              # Pre-select host
#   ./install.sh -h HOST -s KEY -p PWD -y  # Fully automated
#   ./install.sh --dry-run            # Test phases 1-5 without changes
#
# Phases:
#   1. Environment validation
#   2. Host selection
#   3. Feature detection (nix eval)
#   4. Interactive prompts (conditional)
#   5. Summary + confirmation
#   6. State version detection
#   7. Disko partitioning
#   8. NixOS installation
#   9. Post-install setup (SSH, SOPS, TOTP)

set -euo pipefail

#===========================
# CLI Arguments
#===========================

HOST=""
SSH_KEY=""
LUKS_PASSWORD=""
YES=false
DRY_RUN=false
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--host)           HOST="$2"; shift 2 ;;
    -s|--ssh-key)        SSH_KEY="$2"; shift 2 ;;
    -p|--luks-password)  LUKS_PASSWORD="$2"; shift 2 ;;
    -y|--yes)            YES=true; shift ;;
    --dry-run)           DRY_RUN=true; shift ;;
    *)
      echo "Usage: $0 [-h HOST] [-s SSH_KEY] [-p LUKS_PASSWORD] [-y] [--dry-run]"
      exit 1
      ;;
  esac
done

#===========================
# Colors & Helpers
#===========================

if [[ -t 1 ]]; then
  RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m'
  BLUE='\033[0;34m' BOLD='\033[1m' DIM='\033[2m' RESET='\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' BOLD='' DIM='' RESET=''
fi

STEP_CURRENT=0
STEP_TOTAL=0

info()    { echo -e "${BLUE}==>${RESET} ${BOLD}$*${RESET}"; }
success() { echo -e "    ${GREEN}$*${RESET}"; }
warn()    { echo -e "${YELLOW}!!${RESET} $*"; }
error()   { echo -e "${RED}ERROR:${RESET} $*" >&2; exit 1; }
step()    { STEP_CURRENT=$((STEP_CURRENT + 1)); echo ""; info "[$STEP_CURRENT/$STEP_TOTAL] $*"; }

label_bool() { [[ "$1" == "true" ]] && echo -e "${GREEN}enabled${RESET}" || echo -e "${DIM}disabled${RESET}"; }

#===========================
# Phase 1: Environment
#===========================

phase_validate() {
  info "NixOS Installer"
  echo ""

  if [[ "$DRY_RUN" == true ]]; then
    warn "Dry-run mode: no changes will be made"
    echo ""
  fi

  [[ $EUID -eq 0 ]] || error "Must run as root."

  command -v nix &>/dev/null || error "Nix is not available."

  export NIX_CONFIG="experimental-features = nix-command flakes"

  success "Environment OK"
}

#===========================
# Phase 2: Host Selection
#===========================

phase_select_host() {
  local hosts=()
  local descriptions=()

  for dir in "$REPO_DIR"/hosts/*/; do
    local name
    name="$(basename "$dir")"
    [[ -f "$dir/configuration.nix" ]] || continue
    hosts+=("$name")
    # Extract description from first comment line of configuration.nix
    local desc
    desc="$(head -1 "$dir/configuration.nix" | sed 's/^# *//' | sed 's/ *$//')"
    descriptions+=("$desc")
  done

  [[ ${#hosts[@]} -gt 0 ]] || error "No hosts found in $REPO_DIR/hosts/"

  # Validate pre-selected host
  if [[ -n "$HOST" ]]; then
    local found=false
    for h in "${hosts[@]}"; do
      [[ "$h" == "$HOST" ]] && found=true
    done
    [[ "$found" == true ]] || error "Host '$HOST' not found. Available: ${hosts[*]}"
    return
  fi

  # Interactive selection
  echo ""
  info "Available hosts:"
  echo ""
  for i in "${!hosts[@]}"; do
    echo -e "    ${BOLD}[$((i+1))]${RESET} ${hosts[$i]}  ${DIM}— ${descriptions[$i]}${RESET}"
  done
  echo ""

  local choice
  read -rp "    Select host [1-${#hosts[@]}]: " choice

  if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#hosts[@]} )); then
    HOST="${hosts[$((choice-1))]}"
  else
    error "Invalid selection."
  fi
}

#===========================
# Phase 3: Feature Detection
#===========================

# Feature variables (populated by detect_features)
FEAT_ENCRYPTION=false
FEAT_IMPERMANENCE=false
PERSIST_PREFIX=""
FEAT_TOTP=false
FEAT_SECURE_BOOT=false
FEAT_DESKTOP=false
FEAT_WM=""
FEAT_SERVER=false
CONFIG_USERNAME=""
CONFIG_PASSWORD_LOCKED=false

phase_detect_features() {
  info "Reading configuration for $HOST..."

  local json
  json=$(nix eval --json "$REPO_DIR#nixosConfigurations.${HOST}.config" --apply '
    cfg: {
      encryption = cfg.features.encryption.enable;
      impermanence = cfg.features.impermanence.enable;
      persistPrefix = cfg.features.impermanence.persistPrefix;
      totp = cfg.features.auth.totp.enable;
      secureBoot = cfg.features.secureBoot.enable;
      desktop = cfg.features.desktop.enable;
      wm = cfg.features.desktop.wm;
      server = cfg.features.server;
      userName = cfg.user.name;
      passwordLocked = cfg.user.hashedPassword == "!";
    }
  ') || error "Failed to evaluate configuration. Check flake syntax."

  # Ensure jq is available (not on NixOS ISO by default)
  if ! command -v jq &>/dev/null; then
    nix-env -iA nixos.jq 2>/dev/null
  fi

  read -r FEAT_ENCRYPTION FEAT_IMPERMANENCE PERSIST_PREFIX FEAT_TOTP \
          FEAT_SECURE_BOOT FEAT_DESKTOP FEAT_WM FEAT_SERVER CONFIG_USERNAME \
          CONFIG_PASSWORD_LOCKED \
    < <(echo "$json" | jq -r '[
      .encryption, .impermanence, .persistPrefix, .totp,
      .secureBoot, .desktop, .wm, .server, .userName,
      .passwordLocked
    ] | @tsv')

  success "Features detected"
  echo ""
  echo -e "    Host:          ${BOLD}$HOST${RESET}"
  echo -e "    Username:      ${BOLD}$CONFIG_USERNAME${RESET}"
  if [[ "$FEAT_SERVER" == "true" ]]; then
    echo -e "    Mode:          ${BOLD}Server${RESET}"
  elif [[ "$FEAT_DESKTOP" == "true" ]]; then
    echo -e "    Desktop:       ${BOLD}$FEAT_WM${RESET}"
  fi
  echo -e "    Encryption:    $(label_bool "$FEAT_ENCRYPTION")"
  echo -e "    Impermanence:  $(label_bool "$FEAT_IMPERMANENCE")"
  echo -e "    TOTP 2FA:      $(label_bool "$FEAT_TOTP")"
  echo -e "    Secure Boot:   $(label_bool "$FEAT_SECURE_BOOT")"
  if [[ "$CONFIG_PASSWORD_LOCKED" == "true" ]]; then
    echo -e "    Password:      ${YELLOW}not set${RESET}"
  else
    echo -e "    Password:      ${GREEN}set in config${RESET}"
  fi
}

#===========================
# Phase 4: Prompts
#===========================

SSH_KEY_FILE=""
AGE_KEY=""
USER_PASSWORD_HASH=""

phase_collect_inputs() {
  # --- LUKS Password ---
  if [[ "$FEAT_ENCRYPTION" == "true" ]]; then
    echo ""
    if [[ -f /tmp/luks-password ]]; then
      info "Using existing /tmp/luks-password"
    elif [[ -n "$LUKS_PASSWORD" ]]; then
      echo "$LUKS_PASSWORD" > /tmp/luks-password
      chmod 600 /tmp/luks-password
      success "LUKS password set via -p"
    elif [[ "$YES" == true ]]; then
      error "Encryption enabled but no LUKS password. Use -p PASSWORD or pre-create /tmp/luks-password."
    else
      info "LUKS Disk Encryption"
      local pass pass_confirm
      read -rsp "    Enter LUKS password: " pass; echo
      read -rsp "    Confirm password:    " pass_confirm; echo
      [[ "$pass" == "$pass_confirm" ]] || error "Passwords do not match."
      echo "$pass" > /tmp/luks-password
      chmod 600 /tmp/luks-password
      success "Password saved"
    fi
  fi

  # --- SSH Key ---
  echo ""
  info "SSH Key (required for SOPS secrets)"
  if [[ -n "$SSH_KEY" ]]; then
    SSH_KEY_FILE="$SSH_KEY"
    [[ -f "$SSH_KEY_FILE" ]] || error "SSH key file not found: $SSH_KEY_FILE"
  elif [[ "$YES" == true ]]; then
    error "SSH key required. Use -s /path/to/key."
  else
    echo ""
    echo -e "    ${BOLD}[1]${RESET} Enter file path"
    echo -e "    ${BOLD}[2]${RESET} Paste key content"
    echo ""
    local choice
    read -rp "    Choice [1-2]: " choice

    case "$choice" in
      1)
        read -rp "    Path to SSH private key: " SSH_KEY_FILE
        [[ -f "$SSH_KEY_FILE" ]] || error "File not found: $SSH_KEY_FILE"
        ;;
      2)
        echo "    Paste your ed25519 private key (end with Ctrl+D):"
        SSH_KEY_FILE="$(mktemp)"
        cat > "$SSH_KEY_FILE"
        chmod 600 "$SSH_KEY_FILE"
        ;;
      *)
        error "Invalid choice."
        ;;
    esac
  fi
  success "SSH key ready"

  # --- User Password ---
  if [[ "$CONFIG_PASSWORD_LOCKED" == "true" ]]; then
    echo ""
    warn "No password set in host config — account would be locked after install."
    info "User Password"
    local pass pass_confirm
    read -rsp "    Enter password for $CONFIG_USERNAME: " pass; echo
    read -rsp "    Confirm password:    " pass_confirm; echo
    [[ "$pass" == "$pass_confirm" ]] || error "Passwords do not match."
    if command -v mkpasswd &>/dev/null; then
      USER_PASSWORD_HASH="$(echo "$pass" | mkpasswd -m sha-512 -s)"
    else
      USER_PASSWORD_HASH="$(echo "$pass" | nix-shell -p mkpasswd --run 'mkpasswd -m sha-512 -s')"
    fi
    success "Password hash generated"
  fi
}

#===========================
# Phase 5: Summary
#===========================

phase_summary() {
  local host_dir="$REPO_DIR/hosts/$HOST"

  echo ""
  echo -e "${BOLD}============================================${RESET}"
  echo -e "${BOLD}  Installation Summary${RESET}"
  echo -e "${BOLD}============================================${RESET}"
  echo ""
  echo -e "  Host:           $HOST"
  echo -e "  Username:       $CONFIG_USERNAME"
  echo ""
  echo -e "  ${BOLD}Disk Setup:${RESET}"
  if [[ "$FEAT_ENCRYPTION" == "true" ]]; then
    echo -e "    Encryption:   LUKS (password set)"
  else
    echo -e "    Encryption:   none"
  fi
  echo -e "    Filesystem:   btrfs with subvolumes"
  if [[ "$FEAT_IMPERMANENCE" == "true" ]]; then
    echo -e "    Impermanence: enabled (persist: $PERSIST_PREFIX)"
  else
    echo -e "    Impermanence: disabled"
  fi
  echo ""
  echo -e "  ${BOLD}Post-Install:${RESET}"
  if [[ -n "$USER_PASSWORD_HASH" ]]; then
    echo -e "    Password:     will be written to config"
  fi
  echo -e "    SSH key:      will be installed"
  echo -e "    SOPS:         age key from SSH key"
  if [[ "$FEAT_TOTP" == "true" ]]; then
    echo -e "    TOTP 2FA:     will be configured"
  fi
  echo ""
  echo -e "  ${RED}${BOLD}WARNING: This will ERASE all data on the configured disks!${RESET}"
  echo ""

  if [[ "$DRY_RUN" == true ]]; then
    success "Dry-run complete. No changes were made."
    exit 0
  fi

  if [[ "$YES" != true ]]; then
    local confirm
    read -rp "  Continue? [y/N]: " confirm
    [[ "$confirm" =~ ^[yY]$ ]] || { echo "Aborted."; exit 0; }
  fi
}

#===========================
# Phase 6: State Version
#===========================

phase_state_version() {
  local host_dir="$REPO_DIR/hosts/$HOST"

  local version
  version="$(nixos-version | cut -d. -f1,2)"
  success "NixOS version: $version"

  sed -i "s|system\.stateVersion = \"[^\"]*\"|system.stateVersion = \"$version\"|" \
    "$host_dir/configuration.nix"

  if [[ -f "$host_dir/home.nix" ]]; then
    sed -i "s|home\.stateVersion = \"[^\"]*\"|home.stateVersion = \"$version\"|" \
      "$host_dir/home.nix"
  fi

  # Write generated password hash into host config
  if [[ -n "$USER_PASSWORD_HASH" ]]; then
    if grep -q 'user\.hashedPassword' "$host_dir/configuration.nix"; then
      sed -i "s|user\.hashedPassword = \"[^\"]*\"|user.hashedPassword = \"$USER_PASSWORD_HASH\"|" \
        "$host_dir/configuration.nix"
    else
      # Append before closing brace
      sed -i "\$i\\  user.hashedPassword = \"$USER_PASSWORD_HASH\";" \
        "$host_dir/configuration.nix"
    fi
    success "Password hash written to configuration.nix"
  fi

  git -C "$REPO_DIR" add "$host_dir/"
}

#===========================
# Phase 7: Disko
#===========================

phase_partition() {
  # shellcheck disable=SC2054  # comma is disko syntax, not array separator
  local disko_args=(--mode destroy,format,mount --flake "$REPO_DIR#$HOST")
  if [[ "$YES" == true ]]; then
    disko_args+=(--yes-wipe-all-disks)
  fi

  if ! nix run github:nix-community/disko -- "${disko_args[@]}"; then
    error "Disko failed. Check disk IDs in hosts/$HOST/disko.nix"
  fi

  success "Disks partitioned and mounted at /mnt"
}

#===========================
# Phase 8: NixOS Install
#===========================

phase_install() {
  local host_dir="$REPO_DIR/hosts/$HOST"

  nixos-generate-config --root /mnt --show-hardware-config > "$host_dir/hardware-configuration.generated.nix"
  git -C "$REPO_DIR" add --all

  if ! nixos-install --flake "$REPO_DIR#$HOST" --no-root-password; then
    error "nixos-install failed. Check the output above."
  fi

  success "NixOS installed"
}

#===========================
# Phase 9: Post-Install
#===========================

setup_ssh() {
  AGE_KEY="$(nix-shell -p ssh-to-age --run "ssh-to-age -private-key -i $SSH_KEY_FILE")"

  local ssh_dir="/mnt/home/$CONFIG_USERNAME/.ssh"
  mkdir -p "$ssh_dir"
  cp "$SSH_KEY_FILE" "$ssh_dir/id_ed25519"
  ssh-keygen -y -f "$SSH_KEY_FILE" > "$ssh_dir/id_ed25519.pub"
  chmod 700 "$ssh_dir"
  chmod 600 "$ssh_dir/id_ed25519"
  chmod 644 "$ssh_dir/id_ed25519.pub"

  # Clean up temp file if pasted interactively
  [[ -n "$SSH_KEY" ]] || rm -f "$SSH_KEY_FILE"

  success "SSH key installed"
}

setup_sops() {
  local user_dir="/mnt/home/$CONFIG_USERNAME/.config/sops/age"
  local system_dir="/mnt${PERSIST_PREFIX}/var/lib/sops/age"

  mkdir -p "$user_dir" "$system_dir"
  echo "$AGE_KEY" > "$user_dir/keys.txt"
  echo "$AGE_KEY" > "$system_dir/keys.txt"
  chmod 600 "$user_dir/keys.txt" "$system_dir/keys.txt"

  success "SOPS age key saved"
}

setup_totp() {
  local secret_hex secret_b32 oath_file
  secret_hex=$(od -An -tx1 -N20 /dev/urandom | tr -d ' \n')
  secret_b32=$(python3 -c "import base64; print(base64.b32encode(bytes.fromhex('$secret_hex')).decode())")

  oath_file="/mnt${PERSIST_PREFIX}/etc/users.oath"
  mkdir -p "$(dirname "$oath_file")"
  echo "HOTP/T30/6 $CONFIG_USERNAME - $secret_hex" > "$oath_file"
  chmod 600 "$oath_file"

  echo ""
  info "Scan this QR code with your authenticator app:"
  echo ""
  nix-shell -p qrencode --run \
    "qrencode -t ANSIUTF8 'otpauth://totp/${CONFIG_USERNAME}@${HOST}?secret=${secret_b32}&issuer=NixOS'"
  echo ""
  echo -e "    Backup secret (base32): ${BOLD}$secret_b32${RESET}"
  echo ""

  # Verify OTP before confirming
  local verified=false
  for _ in 1 2 3; do
    read -rp "  Enter OTP code to verify: " otp_code
    local expected
    expected=$(nix-shell -p oath-toolkit --run "oathtool --totp -d 6 $secret_hex")
    if [[ "$otp_code" == "$expected" ]]; then
      verified=true
      break
    fi
    warn "Incorrect. Try again."
  done

  if [[ "$verified" != "true" ]]; then
    warn "Verification failed. Removing secret."
    rm -f "$oath_file"
    return 1
  fi

  success "TOTP configured"
}

copy_config() {
  local dest="/mnt/home/$CONFIG_USERNAME/repos/nix"
  if [[ ! -d "$dest" ]]; then
    mkdir -p "/mnt/home/$CONFIG_USERNAME/repos"
    cp -r "$REPO_DIR" "$dest"
    success "Config copied to ~/repos/nix"
  fi
}

phase_post_install() {
  setup_ssh
  setup_sops

  if [[ "$FEAT_TOTP" == "true" ]]; then
    if ! setup_totp; then
      warn "TOTP setup failed. Run 'totp-init' after first boot."
    fi
  fi

  if ! copy_config; then
    warn "Config copy failed. Clone the repo manually after boot."
  fi

  info "Fixing home directory ownership..."
  nixos-enter --root /mnt -c "chown -R $CONFIG_USERNAME:users /home/$CONFIG_USERNAME"

  # Cleanup
  rm -f /tmp/luks-password
}

#===========================
# Phase 10: Done
#===========================

phase_complete() {
  echo ""
  echo -e "${BOLD}============================================${RESET}"
  echo -e "${GREEN}${BOLD}  Installation complete!${RESET}"
  echo -e "${BOLD}============================================${RESET}"
  echo ""

  if [[ "$FEAT_ENCRYPTION" == "true" ]]; then
    echo "  LUKS: Enter disk encryption password at boot"
  fi

  echo "  Login: Password is set in NixOS config"

  if [[ "$FEAT_TOTP" == "true" ]]; then
    echo "  TOTP: Use the code from your authenticator app"
  fi

  if [[ "$FEAT_SECURE_BOOT" == "true" ]]; then
    echo ""
    echo -e "  ${BOLD}Secure Boot (post-install):${RESET}"
    echo "    1. Boot into the new system"
    echo "    2. sudo sbctl create-keys"
    echo "    3. sudo nixos-rebuild switch --flake ~/repos/nix#$HOST"
    echo "    4. sudo sbctl enroll-keys --microsoft"
    echo "    5. Reboot, enable Secure Boot in UEFI"
  fi

  echo ""
  echo "  You can reboot now."
  echo ""
}

#===========================
# Main
#===========================

main() {
  phase_validate
  phase_select_host
  phase_detect_features
  phase_collect_inputs

  phase_summary

  # Destructive phases
  STEP_TOTAL=4

  step "Detecting NixOS version"
  phase_state_version

  step "Partitioning disks"
  phase_partition

  step "Installing NixOS"
  phase_install

  step "Post-install setup"
  phase_post_install

  phase_complete
}

main
