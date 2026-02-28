#!/usr/bin/env bash
# NixOS Interactive Installer
#
# Smart-hybrid installer that reads the host's configuration to determine
# which features are enabled, and only prompts for relevant setup steps.
#
# Usage:
#   ./install.sh                              # Full install (all steps)
#   ./install.sh --host mythinkpad            # Pre-select host
#   ./install.sh --install --post-install     # Reinstall without formatting
#   ./install.sh --post-install               # Re-run post-install only
#   ./install.sh --dry-run                    # Show summary and exit
#   ./install.sh -h                           # Show help
#
# Steps (combinable, default: all):
#   --format        Partition and format disks (disko)
#   --install       Install NixOS (nixos-install)
#   --post-install  Post-install setup (SSH, SOPS, TOTP, YubiKey, TPM/FIDO2)

set -euo pipefail

#===========================
# CLI Arguments
#===========================

HOST=""
SSH_KEY=""
LUKS_PASSWORD=""
YES=false
DRY_RUN=false
DO_FORMAT=false
DO_INSTALL=false
DO_POST_INSTALL=false
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_FILE="/tmp/nix-installer.env"

show_help() {
  cat <<'EOF'
NixOS Interactive Installer

Usage: install.sh [options]

Steps (combinable, default: all):
  --format           Partition and format disks (disko)
  --install          Install NixOS (nixos-install)
  --post-install     Post-install setup (SSH, SOPS, TOTP, YubiKey, TPM/FIDO2)

Options:
  --host HOST        Pre-select host configuration
  -s, --ssh-key PATH Path to SSH private key
  -p, --luks-password PWD  LUKS encryption password
  -y, --yes          Skip confirmation prompts
  --dry-run          Show summary and exit
  -h, --help         Show this help

Examples:
  install.sh                              Full install (all steps)
  install.sh --host mythinkpad            Pre-select host
  install.sh --install --post-install     Reinstall without formatting
  install.sh --post-install               Re-run post-install only
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)           show_help ;;
    --host)              HOST="$2"; shift 2 ;;
    -s|--ssh-key)        SSH_KEY="$2"; shift 2 ;;
    -p|--luks-password)  LUKS_PASSWORD="$2"; shift 2 ;;
    -y|--yes)            YES=true; shift ;;
    --dry-run)           DRY_RUN=true; shift ;;
    --format)            DO_FORMAT=true; shift ;;
    --install)           DO_INSTALL=true; shift ;;
    --post-install)      DO_POST_INSTALL=true; shift ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Run '$0 --help' for usage information." >&2
      exit 1
      ;;
  esac
done

# Default: all steps if none specified
if [[ "$DO_FORMAT" == false && "$DO_INSTALL" == false && "$DO_POST_INSTALL" == false ]]; then
  DO_FORMAT=true
  DO_INSTALL=true
  DO_POST_INSTALL=true
fi

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
# State Persistence
#===========================

load_state() {
  if [[ -f "$STATE_FILE" ]]; then
    echo ""
    info "Resuming previous session"
    # Save CLI values before sourcing (CLI has priority)
    local cli_host="$HOST" cli_ssh="$SSH_KEY_FILE" cli_password="$USER_PASSWORD_HASH"
    # shellcheck source=/dev/null
    source "$STATE_FILE"
    # Restore CLI values where set
    [[ -n "$cli_host" ]] && HOST="$cli_host"
    [[ -n "$cli_ssh" ]] && SSH_KEY_FILE="$cli_ssh"
    [[ -n "$cli_password" ]] && USER_PASSWORD_HASH="$cli_password"
    success "Loaded: host=$HOST"
  fi
}

save_state() {
  cat > "$STATE_FILE" <<EOF
HOST="$HOST"
SSH_KEY_FILE="$SSH_KEY_FILE"
USER_PASSWORD_HASH="$USER_PASSWORD_HASH"
EOF
  chmod 600 "$STATE_FILE"
}

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

  # shellcheck disable=SC2046
  echo -e "    Steps: ${BOLD}$(printf '%s ' \
    $([[ "$DO_FORMAT" == true ]] && echo "format") \
    $([[ "$DO_INSTALL" == true ]] && echo "install") \
    $([[ "$DO_POST_INSTALL" == true ]] && echo "post-install"))${RESET}"
  echo ""

  [[ $EUID -eq 0 ]] || error "Must run as root."

  command -v nix &>/dev/null || error "Nix is not available."

  export NIX_CONFIG="experimental-features = nix-command flakes
warn-dirty = false"

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
FEAT_YUBIKEY=false
FEAT_YUBIKEY_LUKS=false
FEAT_SECURE_BOOT=false
FEAT_DESKTOP=false
FEAT_WM=""
FEAT_SERVER=false
CONFIG_USERNAME=""
CONFIG_PASSWORD_LOCKED=false
LUKS_DEVICES=()
TPM_ENROLLED=false
FIDO2_LUKS_ENROLLED=false

phase_detect_features() {
  echo ""
  info "Reading configuration for $HOST..."

  local json
  json=$(nix eval --json "$REPO_DIR#nixosConfigurations.${HOST}.config" --apply '
    cfg: {
      encryption = cfg.features.encryption.enable;
      impermanence = cfg.features.impermanence.enable;
      persistPrefix = cfg.features.impermanence.persistPrefix;
      totp = cfg.features.auth.totp.enable;
      yubikey = cfg.features.auth.yubikey.enable;
      yubikeyLuks = cfg.features.auth.yubikey.luks.enable;
      secureBoot = cfg.features.secureBoot.enable;
      desktop = cfg.features.desktop.enable;
      wm = cfg.features.desktop.wm;
      server = cfg.features.server;
      userName = cfg.user.name;
      passwordLocked = cfg.user.hashedPassword == "!";
      luksDevices = builtins.attrValues (builtins.mapAttrs (name: dev: dev.device) cfg.boot.initrd.luks.devices);
    }
  ') || error "Failed to evaluate configuration. Check flake syntax."

  # Ensure jq is available (not on NixOS ISO by default)
  if ! command -v jq &>/dev/null; then
    nix-env -iA nixos.jq 2>/dev/null
  fi

  read -r FEAT_ENCRYPTION FEAT_IMPERMANENCE PERSIST_PREFIX FEAT_TOTP \
          FEAT_YUBIKEY FEAT_YUBIKEY_LUKS FEAT_SECURE_BOOT FEAT_DESKTOP FEAT_WM FEAT_SERVER \
          CONFIG_USERNAME CONFIG_PASSWORD_LOCKED \
    < <(echo "$json" | jq -r '[
      .encryption, .impermanence, .persistPrefix, .totp,
      .yubikey, .yubikeyLuks, .secureBoot, .desktop, .wm, .server, .userName,
      .passwordLocked
    ] | @tsv')

  # Parse LUKS device paths into array
  mapfile -t LUKS_DEVICES < <(echo "$json" | jq -r '.luksDevices[]')

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
  echo -e "    YubiKey:       $(label_bool "$FEAT_YUBIKEY")"
  echo -e "    Secure Boot:   $(label_bool "$FEAT_SECURE_BOOT")"
  if [[ "$FEAT_ENCRYPTION" == "true" && ${#LUKS_DEVICES[@]} -gt 0 ]]; then
    echo -e "    LUKS devices:  ${DIM}${#LUKS_DEVICES[@]} partition(s)${RESET}"
    echo -e "    LUKS Unlock:   $(label_bool "$FEAT_YUBIKEY_LUKS") (YubiKey FIDO2)"
  fi
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
  # --- LUKS Password (needed for format, mount, or post-install with TPM enrollment) ---
  if [[ "$FEAT_ENCRYPTION" == "true" ]] && [[ "$DO_FORMAT" == true || "$DO_INSTALL" == true || "$DO_POST_INSTALL" == true ]]; then
    echo ""
    if [[ -f /tmp/luks-password ]]; then
      info "Using existing /tmp/luks-password"
    elif [[ -n "$LUKS_PASSWORD" ]]; then
      printf '%s' "$LUKS_PASSWORD" > /tmp/luks-password
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
      printf '%s' "$pass" > /tmp/luks-password
      chmod 600 /tmp/luks-password
      success "Password saved"
    fi
  fi

  # --- SSH Key (only needed for post-install) ---
  if [[ "$DO_POST_INSTALL" == true ]]; then
    echo ""
    info "SSH Key (required for SOPS secrets)"
    if [[ -n "$SSH_KEY_FILE" && -f "$SSH_KEY_FILE" ]]; then
      success "SSH key ready (cached)"
    elif [[ -n "$SSH_KEY" ]]; then
      SSH_KEY_FILE="$SSH_KEY"
      [[ -f "$SSH_KEY_FILE" ]] || error "SSH key file not found: $SSH_KEY_FILE"
      success "SSH key ready"
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
      success "SSH key ready"
    fi
  fi

  # --- User Password ---
  if [[ "$CONFIG_PASSWORD_LOCKED" == "true" ]]; then
    echo ""
    if [[ -n "$USER_PASSWORD_HASH" ]]; then
      success "Password hash ready (cached)"
    else
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
  fi

  save_state
}

#===========================
# Phase 5: Summary
#===========================

phase_summary() {
  echo ""
  echo -e "${BOLD}============================================${RESET}"
  echo -e "${BOLD}  Installation Summary${RESET}"
  echo -e "${BOLD}============================================${RESET}"
  echo ""
  echo -e "    Host:           $HOST"
  echo -e "    Username:       $CONFIG_USERNAME"
  # shellcheck disable=SC2046
  echo -e "    Steps:          $(printf '%s ' \
    $([[ "$DO_FORMAT" == true ]] && echo "format") \
    $([[ "$DO_INSTALL" == true ]] && echo "install") \
    $([[ "$DO_POST_INSTALL" == true ]] && echo "post-install"))"
  echo ""
  if [[ "$DO_FORMAT" == true ]]; then
    echo -e "    ${BOLD}Disk Setup:${RESET}"
    if [[ "$FEAT_ENCRYPTION" == "true" ]]; then
      echo -e "      Encryption:   LUKS (password set)"
    else
      echo -e "      Encryption:   none"
    fi
    echo -e "      Filesystem:   btrfs with subvolumes"
    if [[ "$FEAT_IMPERMANENCE" == "true" ]]; then
      echo -e "      Impermanence: enabled (persist: $PERSIST_PREFIX)"
    else
      echo -e "      Impermanence: disabled"
    fi
    echo ""
  fi
  if [[ "$DO_POST_INSTALL" == true ]]; then
    echo -e "    ${BOLD}Post-Install:${RESET}"
    if [[ -n "$USER_PASSWORD_HASH" ]]; then
      echo -e "      Password:     will be written to config"
    fi
    echo -e "      SSH key:      will be installed"
    echo -e "      SOPS:         age key from SSH key"
    if [[ "$FEAT_TOTP" == "true" ]]; then
      echo -e "      TOTP 2FA:     will be configured"
    fi
    if [[ "$FEAT_YUBIKEY" == "true" ]]; then
      echo -e "      YubiKey:      will be configured"
    fi
    echo ""
  fi
  if [[ "$DO_FORMAT" == true ]]; then
    echo -e "    ${RED}${BOLD}WARNING: This will ERASE all data on the configured disks!${RESET}"
  fi
  echo ""

  if [[ "$DRY_RUN" == true ]]; then
    success "Dry-run complete. No changes were made."
    exit 0
  fi

  if [[ "$YES" != true ]]; then
    local confirm
    read -rp "    Continue? [y/N]: " confirm
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

phase_mount() {
  local disko_args=(--mode mount --flake "$REPO_DIR#$HOST")

  if ! nix run github:nix-community/disko -- "${disko_args[@]}"; then
    error "Disko mount failed. Are the disks connected?"
  fi

  success "Existing disks mounted at /mnt"
}

#===========================
# Phase 8: NixOS Install
#===========================

phase_install() {
  local host_dir="$REPO_DIR/hosts/$HOST"

  nixos-generate-config --root /mnt --show-hardware-config > "$host_dir/hardware-configuration.generated.nix"
  nix flake lock "$REPO_DIR"
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
  secret_b32=$(printf '%s' "$secret_hex" | sed 's/../\\x&/g' | xargs -0 printf '%b' | base32 | tr -d '\n')

  oath_file="/mnt${PERSIST_PREFIX}/etc/users.oath"
  mkdir -p "$(dirname "$oath_file")"
  echo "HOTP/T30/6 $CONFIG_USERNAME - $secret_hex" > "$oath_file"
  chmod 600 "$oath_file"

  echo ""
  info "Scan this QR code with your authenticator app:"
  echo ""
  nix-shell -p qrencode --run \
    "qrencode -t ANSIUTF8 'otpauth://totp/NixOS:${CONFIG_USERNAME}@${HOST}?secret=${secret_b32}&issuer=NixOS'"
  echo ""
  echo -e "    Backup secret (base32): ${BOLD}$secret_b32${RESET}"
  echo ""

  # Verify OTP before confirming
  local verified=false
  for _ in 1 2 3; do
    read -rp "    Enter OTP code to verify: " otp_code
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

setup_yubikey() {
  local mappings_file="/mnt${PERSIST_PREFIX}/etc/u2f_mappings"
  mkdir -p "$(dirname "$mappings_file")"

  info "Insert your YubiKey and press the button when prompted..."
  echo ""

  local credentials
  credentials=$(nix-shell -p pam_u2f --run "pamu2fcfg -u $CONFIG_USERNAME")
  if [[ -z "$credentials" ]]; then
    return 1
  fi

  echo "$credentials" > "$mappings_file"
  chmod 600 "$mappings_file"

  success "YubiKey registered for $CONFIG_USERNAME"
}

setup_tpm() {
  # TPM hardware present?
  [[ -c /dev/tpmrm0 ]] || { warn "No TPM2 device found, skipping."; return 1; }

  # systemd-cryptenroll available?
  if ! command -v systemd-cryptenroll &>/dev/null; then
    warn "systemd-cryptenroll not available, skipping TPM enrollment."
    return 1
  fi

  # LUKS password: from /tmp/luks-password or interactive prompt
  local password_file="/tmp/luks-password"
  if [[ ! -f "$password_file" ]]; then
    local password
    read -rsp "    LUKS password for TPM enrollment: " password; echo
    printf '%s' "$password" > "$password_file"
    chmod 600 "$password_file"
  fi

  local pcrs="0+7"
  for dev in "${LUKS_DEVICES[@]}"; do
    info "Enrolling TPM2 on $(basename "$dev")..."
    if systemd-cryptenroll "$dev" --tpm2-device=auto --tpm2-pcrs="$pcrs" --unlock-key-file="$password_file"; then
      success "$(basename "$dev") enrolled"
    else
      warn "$(basename "$dev") failed"
      return 1
    fi
  done

  TPM_ENROLLED=true
}

setup_yubikey_luks() {
  # YubiKey must be present
  if ! command -v systemd-cryptenroll &>/dev/null; then
    warn "systemd-cryptenroll not available, skipping FIDO2 enrollment."
    return 1
  fi

  # LUKS password: from /tmp/luks-password or interactive prompt
  local password_file="/tmp/luks-password"
  if [[ ! -f "$password_file" ]]; then
    local password
    read -rsp "    LUKS password for FIDO2 enrollment: " password; echo
    printf '%s' "$password" > "$password_file"
    chmod 600 "$password_file"
  fi

  for dev in "${LUKS_DEVICES[@]}"; do
    info "Enrolling FIDO2 on $(basename "$dev")..."
    if systemd-cryptenroll "$dev" --fido2-device=auto --unlock-key-file="$password_file"; then
      success "$(basename "$dev") enrolled"
    else
      warn "$(basename "$dev") enrollment failed"
      return 1
    fi
  done

  FIDO2_LUKS_ENROLLED=true
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
    local oath_file="/mnt${PERSIST_PREFIX}/etc/users.oath"
    if [[ -f "$oath_file" ]]; then
      success "TOTP already configured (cached)"
    elif ! setup_totp; then
      warn "TOTP setup failed. Run 'totp-init' after first boot."
    fi
  fi

  if [[ "$FEAT_YUBIKEY" == "true" ]]; then
    local mappings_file="/mnt${PERSIST_PREFIX}/etc/u2f_mappings"
    if [[ -f "$mappings_file" ]]; then
      success "YubiKey already configured (cached)"
    elif ! setup_yubikey; then
      warn "YubiKey setup failed. Run 'yubikey-init' after first boot."
    fi
  fi

  if [[ "$FEAT_YUBIKEY_LUKS" == "true" && "$FEAT_ENCRYPTION" == "true" && ${#LUKS_DEVICES[@]} -gt 0 ]]; then
    if ! setup_yubikey_luks; then
      warn "FIDO2 LUKS enrollment skipped. Run 'yubikey-luks-init' after first boot."
    fi
  elif [[ "$FEAT_ENCRYPTION" == "true" && ${#LUKS_DEVICES[@]} -gt 0 ]]; then
    if ! setup_tpm; then
      warn "TPM enrollment skipped. Run 'sudo tpm-luks-init' after first boot."
    fi
  fi

  if ! copy_config; then
    warn "Config copy failed. Clone the repo manually after boot."
  fi

  info "Fixing home directory ownership..."
  nixos-enter --root /mnt -c "chown -R $CONFIG_USERNAME:users /home/$CONFIG_USERNAME"
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
    echo "    LUKS: Enter disk encryption password at boot"
    if [[ "$FIDO2_LUKS_ENROLLED" == "true" ]]; then
      echo "    FIDO2: YubiKey LUKS enrollment done — plug in and tap at boot"
    elif [[ "$TPM_ENROLLED" == "true" ]]; then
      echo "    TPM:  Auto-unlock enrolled (password still works as fallback)"
    fi
  fi

  echo "    Login: Password is set in NixOS config"

  if [[ "$FEAT_TOTP" == "true" ]]; then
    echo "    TOTP: Use the code from your authenticator app"
  fi

  if [[ "$FEAT_YUBIKEY" == "true" ]]; then
    echo "    YubiKey: Touch your key at login prompt"
  fi

  if [[ "$FEAT_SECURE_BOOT" == "true" ]]; then
    echo ""
    echo -e "    ${BOLD}Secure Boot (post-install):${RESET}"
    echo "      1. Boot into the new system"
    echo "      2. sudo sbctl create-keys"
    echo "      3. sudo nixos-rebuild switch --flake ~/repos/nix#$HOST"
    echo "      4. sudo sbctl enroll-keys --microsoft"
    echo "      5. Reboot, enable Secure Boot in UEFI"
  fi

  echo ""
  echo "    You can reboot now."
  echo ""
}

#===========================
# Main
#===========================

main() {
  load_state
  phase_validate
  phase_select_host
  phase_detect_features
  phase_collect_inputs
  phase_summary

  # Mount existing disks via disko if /mnt is not mounted and format was not requested
  if [[ "$DO_FORMAT" != true ]] && [[ "$DO_INSTALL" == true || "$DO_POST_INSTALL" == true ]]; then
    if ! mountpoint -q /mnt 2>/dev/null; then
      DO_MOUNT=true
    fi
  fi

  # Dynamic step count
  STEP_TOTAL=0
  [[ "$DO_FORMAT" == true ]] && STEP_TOTAL=$((STEP_TOTAL + 1))
  [[ "${DO_MOUNT:-false}" == true ]] && STEP_TOTAL=$((STEP_TOTAL + 1))
  [[ "$DO_INSTALL" == true ]] && STEP_TOTAL=$((STEP_TOTAL + 2))  # state version + install
  [[ "$DO_POST_INSTALL" == true ]] && STEP_TOTAL=$((STEP_TOTAL + 1))

  if [[ "$DO_FORMAT" == true ]]; then
    step "Partitioning disks"
    phase_partition
  elif [[ "${DO_MOUNT:-false}" == true ]]; then
    step "Mounting existing disks"
    phase_mount
  fi

  if [[ "$DO_INSTALL" == true ]]; then
    step "Detecting NixOS version"
    phase_state_version
    step "Installing NixOS"
    phase_install
  fi

  if [[ "$DO_POST_INSTALL" == true ]]; then
    step "Post-install setup"
    phase_post_install
  fi

  phase_complete

  # Cleanup
  rm -f /tmp/luks-password "$STATE_FILE"
}

main
