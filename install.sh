#!/usr/bin/env bash
# NixOS Interactive Installer
#
# Smart-hybrid installer that reads the host's configuration to determine
# which features are enabled, and only prompts for relevant setup steps.
#
# Usage:
#   ./install.sh                                        # Full install, all prompts
#   ./install.sh --host samuels-terra                   # Pre-select host
#   ./install.sh --host foo -s key.pem -p luks -y       # Fully non-interactive
#   ./install.sh --install --post-install               # Reinstall without formatting
#   ./install.sh --post-install                         # Re-run post-install only
#   ./install.sh --dry-run                              # Show summary and exit
#   ./install.sh -h                                     # Show help
#
# Steps (combinable, default: all):
#   --format        Partition and format disks (disko)
#   --install       Install NixOS (nixos-install)
#   --post-install  Post-install setup (SSH, SOPS, TOTP, TPM/FIDO2)

set -euo pipefail

#===========================
# CLI Arguments
#===========================

HOST=""
SSH_KEY=""
LUKS_PASSWORD="${LUKS_PASSWORD:-}"
YES=false
DRY_RUN=false
DO_FORMAT=false
DO_INSTALL=false
DO_POST_INSTALL=false
SKIP_TOTP=false
QUIET_UPGRADE=false
REPAIR=false
ORIGINAL_ARGS=("$@")
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
# When invoked via PATH (not from the repo directory), resolve the repo location
# from the running system's nixos-upgrade unit — same source of truth as quickstart.sh.
if [[ ! -f "$REPO_DIR/flake.nix" ]]; then
  REPO_DIR=$(systemctl show nixos-upgrade.service --property=ExecStart 2>/dev/null \
    | grep -o -- '--flake [^ ]*' | awk '{print $2}' | sed 's/#.*//' || true)
  if [[ -z "$REPO_DIR" || ! -f "$REPO_DIR/flake.nix" ]]; then
    USER_HOME="$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)"
    REPO_DIR="$USER_HOME/repos/nix"
  fi
fi
STATE_FILE="/tmp/install.env"
trap 'rm -f /tmp/luks-password "$STATE_FILE"' EXIT

show_help() {
  cat <<'EOF'
NixOS Interactive Installer

Usage: install.sh [options]

Steps (combinable, default: all):
  --format              Partition and format disks (disko)
  --install             Install NixOS (nixos-install)
  --post-install        Post-install setup (SSH, SOPS, TOTP, TPM/FIDO2)

Options:
  --host HOST           Pre-select host configuration
  -s, --ssh-key PATH    Path to SSH private key
  -p, --luks-password   LUKS disk encryption password
  --repair              Force rebuild of already-cached derivations (nixos-rebuild --repair)
  --skip-totp           Skip TOTP setup (deferred to totp-init after first boot)
  -y, --yes             Skip all confirmation prompts (non-interactive mode)
  --dry-run             Show summary and exit without making changes
  -h, --help            Show this help

Non-interactive examples:
  install.sh --host samuels-terra -s /path/to/key.pem -p luks-pw --skip-totp -y

  NIXOS_LUKS_PASSWORD=secret \
  NIXOS_SSH_KEY=/path/to/key \
  install.sh --host samuels-terra --skip-totp -y

Step combinations:
  install.sh                              Full install (all steps)
  install.sh --install --post-install     Reinstall without formatting
  install.sh --post-install               Re-run post-install only
  install.sh --dry-run                    Show what would happen, no changes
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)           show_help ;;
    --host)              HOST="$2"; shift 2 ;;
    -s|--ssh-key)        SSH_KEY="$2"; shift 2 ;;
    -p|--luks-password)  LUKS_PASSWORD="$2"; shift 2 ;;
    --skip-totp)         SKIP_TOTP=true; shift ;;
    --quiet)             QUIET_UPGRADE=true; shift ;;
    --repair)            REPAIR=true; shift ;;
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
success() { echo -e "    ${GREEN}✓${RESET} $*"; }
warn()    { echo -e "    ${YELLOW}!${RESET} $*"; }
error()   { echo -e "${RED}Error:${RESET} $*" >&2; exit 1; }
step()    { STEP_CURRENT=$((STEP_CURRENT + 1)); echo ""; info "[$STEP_CURRENT/$STEP_TOTAL] $*"; }

label_bool() { [[ "$1" == "true" ]] && echo -e "${GREEN}enabled${RESET}" || echo -e "${DIM}disabled${RESET}"; }

#===========================
# State Persistence
#===========================

load_state() {
  if [[ -f "$STATE_FILE" ]]; then
    echo ""
    info "Resuming previous session"
    echo ""
    # Save CLI values before sourcing (CLI has priority)
    local cli_host="$HOST" cli_ssh="$SSH_KEY" cli_luks="$LUKS_PASSWORD"
    # shellcheck source=/dev/null
    source "$STATE_FILE"
    # Restore CLI values where set
    [[ -n "$cli_host" ]] && HOST="$cli_host"
    [[ -n "$cli_luks" ]] && LUKS_PASSWORD="$cli_luks"
    # Restore SSH key: CLI path takes priority, then cached content
    if [[ -n "$cli_ssh" ]]; then
      SSH_KEY="$cli_ssh"
      SSH_KEY_FILE=""
    elif [[ -n "${SSH_KEY_CONTENT:-}" ]]; then
      SSH_KEY_FILE="$(mktemp)"
      printf '%s\n' "$SSH_KEY_CONTENT" > "$SSH_KEY_FILE"
      chmod 600 "$SSH_KEY_FILE"
    fi
    success "Loaded: host=$HOST"
    echo ""
  fi
}

save_state() {
  {
    # Inputs
    printf 'HOST=%q\n' "$HOST"
    printf 'LUKS_PASSWORD=%q\n' "${LUKS_PASSWORD:-}"
    printf 'USER_PASSWORD_HASH=%q\n' "${USER_PASSWORD_HASH:-}"
    # Store key content (not path) so resume works within the same session
    if [[ -n "${SSH_KEY_FILE:-}" && -f "$SSH_KEY_FILE" ]]; then
      printf 'SSH_KEY_CONTENT=%q\n' "$(cat "$SSH_KEY_FILE")"
    else
      printf 'SSH_KEY_CONTENT=%q\n' "${SSH_KEY_CONTENT:-}"
    fi
    # Detected features — cached to avoid re-running nix eval on resume
    printf 'FEAT_ENCRYPTION=%q\n' "${FEAT_ENCRYPTION:-false}"
    printf 'FEAT_IMPERMANENCE=%q\n' "${FEAT_IMPERMANENCE:-false}"
    printf 'PERSIST_PREFIX=%q\n' "${PERSIST_PREFIX:-}"
    printf 'FEAT_TOTP=%q\n' "${FEAT_TOTP:-false}"
    printf 'FEAT_YUBIKEY=%q\n' "${FEAT_YUBIKEY:-false}"
    printf 'FEAT_YUBIKEY_LUKS=%q\n' "${FEAT_YUBIKEY_LUKS:-false}"
    printf 'FEAT_SECURE_BOOT=%q\n' "${FEAT_SECURE_BOOT:-false}"
    printf 'FEAT_DESKTOP=%q\n' "${FEAT_DESKTOP:-false}"
    printf 'FEAT_WM=%q\n' "${FEAT_WM:-}"
    printf 'FEAT_SERVER=%q\n' "${FEAT_SERVER:-false}"
    printf 'CONFIG_USERNAME=%q\n' "${CONFIG_USERNAME:-}"
    printf 'CONFIG_PASSWORD_LOCKED=%q\n' "${CONFIG_PASSWORD_LOCKED:-false}"
    # Progress — prevents double-enrollment if installer crashes after TPM enroll
    printf 'TPM_ENROLLED=%q\n' "${TPM_ENROLLED:-false}"
  } > "$STATE_FILE"
  chmod 600 "$STATE_FILE"
}

#===========================
# Phase 1: Environment
#===========================

# Write LUKS_PASSWORD to /tmp/luks-password for tools that need a file (disko, systemd-cryptenroll)
luks_password_file() {
  printf '%s' "$LUKS_PASSWORD" > /tmp/luks-password
  chmod 600 /tmp/luks-password
  echo /tmp/luks-password
}

phase_validate() {
  # Print header once — suppress after sudo re-elevation
  [[ "${_HEADER_PRINTED:-}" != "1" ]] && { info "NixOS Installer"; echo ""; export _HEADER_PRINTED=1; }

  if [[ ! -e /etc/NIXOS ]]; then
    error "Not a NixOS system. Boot from a NixOS ISO first."
  fi

  if [[ $EUID -ne 0 ]]; then
    exec sudo env _HEADER_PRINTED=1 "$0" "${ORIGINAL_ARGS[@]}"
  fi

  if [[ "$DRY_RUN" == true ]]; then
    warn "Dry-run mode: no changes will be made"
    echo ""
  fi

  local root_fstype
  root_fstype="$(findmnt -n -o FSTYPE /)"
  IS_LIVE=false
  [[ "$root_fstype" == "tmpfs" ]] && IS_LIVE=true

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

  # On an installed system: auto-detect host from current hostname
  if [[ -z "$HOST" && "$IS_LIVE" != true ]]; then
    local current_hostname
    current_hostname="$(hostname)"
    for h in "${hosts[@]}"; do
      if [[ "$h" == "$current_hostname" ]]; then
        HOST="$current_hostname"
        success "Host detected from hostname: $HOST"
        echo ""
        return
      fi
    done
  fi

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

phase_detect_features() {
  # Skip nix eval if features were already detected and cached in the state file
  if [[ -n "$CONFIG_USERNAME" ]]; then
    echo ""
    success "Features loaded from cache (host: $HOST)"
    echo ""
    return
  fi

  echo ""
  info "Reading configuration for $HOST..."
  echo ""

  local json
  json=$(nix eval --json "$REPO_DIR#nixosConfigurations.${HOST}.config" --apply '
    cfg: {
      encryption = cfg.features.encryption.enable;
      impermanence = cfg.features.impermanence.enable;
      persistPrefix = cfg.features.impermanence.persistPrefix;
      totp = cfg.features.auth.totp.enable;
      yubikey = cfg.features.auth.yubikey.enable;
      yubikeyLuks = cfg.features.encryption.unlockMethod == "yubikey";
      secureBoot = cfg.features.secureBoot.enable;
      desktop = cfg.features.desktop.enable;
      wm = cfg.features.desktop.wm;
      server = cfg.features.server;
      userName = cfg.user.name;
      # passwordLocked: true only when hashedPassword = "!" AND no sops secret covers it.
      # When user/password is in sops, user-passwd.service sets the password at boot.
      passwordLocked = cfg.user.hashedPassword == "!"
        && !(cfg.sops.secrets ? "user/password");
      luksDevices = builtins.attrValues (builtins.mapAttrs (name: dev: dev.device) cfg.boot.initrd.luks.devices);
    }
  ') || error "Failed to evaluate configuration. Check flake syntax."

  # Ensure jq is available (not on NixOS ISO by default)
  if ! command -v jq &>/dev/null; then
    nix profile install nixpkgs#jq 2>/dev/null || nix-env -iA nixos.jq 2>/dev/null
  fi

  FEAT_ENCRYPTION=$(echo "$json"      | jq -r '.encryption')
  FEAT_IMPERMANENCE=$(echo "$json"    | jq -r '.impermanence')
  PERSIST_PREFIX=$(echo "$json"       | jq -r '.persistPrefix')
  FEAT_TOTP=$(echo "$json"            | jq -r '.totp')
  FEAT_YUBIKEY=$(echo "$json"         | jq -r '.yubikey')
  FEAT_YUBIKEY_LUKS=$(echo "$json"    | jq -r '.yubikeyLuks')
  FEAT_SECURE_BOOT=$(echo "$json"     | jq -r '.secureBoot')
  FEAT_DESKTOP=$(echo "$json"         | jq -r '.desktop')
  FEAT_WM=$(echo "$json"              | jq -r '.wm')
  FEAT_SERVER=$(echo "$json"          | jq -r '.server')
  CONFIG_USERNAME=$(echo "$json"      | jq -r '.userName')
  CONFIG_PASSWORD_LOCKED=$(echo "$json" | jq -r '.passwordLocked')

  # Parse LUKS device paths into array
  mapfile -t LUKS_DEVICES < <(echo "$json" | jq -r '.luksDevices[]')

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
  if [[ "$CONFIG_PASSWORD_LOCKED" == "true" && -z "$USER_PASSWORD_HASH" ]]; then
    echo -e "    Password:      ${YELLOW}not set${RESET}"
  elif [[ "$CONFIG_PASSWORD_LOCKED" == "false" ]]; then
    echo -e "    Password:      ${GREEN}via sops${RESET}  ${DIM}(set at boot by user-passwd.service)${RESET}"
  else
    echo -e "    Password:      ${GREEN}set in config${RESET}"
  fi
  echo ""
  success "Features detected"
  save_state
}

#===========================
# Phase 4: Prompts
#===========================

SSH_KEY_FILE=""
SSH_KEY_CONTENT=""
AGE_KEY=""
USER_PASSWORD_HASH=""

phase_collect_inputs() {
  # Env-var fallbacks — useful for scripted/CI installs without exposing
  # values in the process list. CLI flags take priority over env vars.
  [[ -z "$LUKS_PASSWORD" && -n "${NIXOS_LUKS_PASSWORD:-}" ]] && LUKS_PASSWORD="$NIXOS_LUKS_PASSWORD"
  [[ -z "$SSH_KEY"       && -n "${NIXOS_SSH_KEY:-}"       ]] && SSH_KEY="$NIXOS_SSH_KEY"

  # --- LUKS Password ---
  # Needed for: format (disko), install (nixos-install), TPM enrollment (post-install).
  # Not needed for: post-install-only when no TPM, YubiKey-LUKS, or TPM-Secure-Boot deferral.
  local need_luks=false
  [[ "$DO_FORMAT" == true || "$DO_INSTALL" == true ]] && need_luks=true
  if [[ "$DO_POST_INSTALL" == true && "$FEAT_ENCRYPTION" == "true" && \
        "$FEAT_YUBIKEY_LUKS" != "true" && "$FEAT_SECURE_BOOT" != "true" ]]; then
    need_luks=true
  fi
  if [[ "$FEAT_ENCRYPTION" == "true" ]] && [[ "$need_luks" == true ]]; then
    echo ""
    if [[ -n "$LUKS_PASSWORD" ]]; then
      success "LUKS password ready (cached)"
    elif [[ "$YES" == true ]]; then
      error "Encryption enabled but no LUKS password. Use -p PASSWORD."
    else
      info "LUKS Disk Encryption"
      echo ""
      local pass pass_confirm
      read -rsp "Enter LUKS password: " pass; echo
      read -rsp "Confirm password: " pass_confirm; echo
      [[ "$pass" == "$pass_confirm" ]] || error "Passwords do not match."
      LUKS_PASSWORD="$pass"
      success "Password saved"
    fi
  fi

  # --- SSH Key (only needed for post-install) ---
  if [[ "$DO_POST_INSTALL" == true ]]; then
    echo ""
    info "SSH Key (required for SOPS secrets)"
    echo ""
    if [[ -n "$SSH_KEY_FILE" && -f "$SSH_KEY_FILE" ]]; then
      success "SSH key ready (cached)"
    elif [[ -n "$SSH_KEY" ]]; then
      SSH_KEY_FILE="$SSH_KEY"
      [[ -f "$SSH_KEY_FILE" ]] || error "SSH key file not found: $SSH_KEY_FILE"
      success "SSH key ready"
    elif [[ "$YES" == true ]]; then
      error "SSH key required for post-install. Use -s /path/to/key or set NIXOS_SSH_KEY."
    else
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
      echo ""
      info "User Password"
      echo ""
      local pass pass_confirm
      read -rsp "Enter password for $CONFIG_USERNAME: " pass; echo
      read -rsp "Confirm password: " pass_confirm; echo
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
    elif [[ "$CONFIG_PASSWORD_LOCKED" == "false" ]]; then
      echo -e "      Password:     from sops (set at boot)"
    fi
    echo -e "      SSH key:      will be installed"
    echo -e "      SOPS:         age key from SSH key"
    if [[ "$FEAT_TOTP" == "true" ]]; then
      if [[ "$SKIP_TOTP" == "true" || "$YES" == "true" ]]; then
        echo -e "      TOTP 2FA:     deferred (run totp-init after first boot)"
      else
        echo -e "      TOTP 2FA:     will be configured interactively"
      fi
    fi
    if [[ "$FEAT_YUBIKEY" == "true" ]]; then
      echo -e "      YubiKey:      registration required after first boot"
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
  version="$(nix eval --raw "$REPO_DIR#nixosConfigurations.${HOST}.pkgs.lib.version" | grep -o '^[0-9]*\.[0-9]*')"
  echo ""
  success "NixOS version: $version"

  sed -i "s|system\.stateVersion = \"[^\"]*\"|system.stateVersion = \"$version\"|" \
    "$host_dir/configuration.nix"

  if [[ -f "$host_dir/home.nix" ]]; then
    sed -i "s|home\.stateVersion = \"[^\"]*\"|home.stateVersion = \"$version\"|" \
      "$host_dir/home.nix"
  fi

  # Write generated password hash into host config.
  # Use python for the substitution — sed interprets $ in the replacement string
  # as a back-reference, which breaks sha-512 hashes that start with $6$.
  if [[ -n "$USER_PASSWORD_HASH" ]]; then
    if grep -q 'user\.hashedPassword' "$host_dir/configuration.nix"; then
      python3 - "$host_dir/configuration.nix" "$USER_PASSWORD_HASH" <<'PYEOF'
import sys, re
path, hash_val = sys.argv[1], sys.argv[2]
with open(path) as f:
    content = f.read()
content = re.sub(
    r'user\.hashedPassword = "[^"]*"',
    f'user.hashedPassword = "{hash_val}"',
    content
)
with open(path, 'w') as f:
    f.write(content)
PYEOF
    else
      python3 - "$host_dir/configuration.nix" "$USER_PASSWORD_HASH" <<'PYEOF'
import sys
path, hash_val = sys.argv[1], sys.argv[2]
with open(path) as f:
    lines = f.readlines()
# Insert before the last closing brace
for i in range(len(lines)-1, -1, -1):
    if lines[i].strip() == '}':
        lines.insert(i, f'  user.hashedPassword = "{hash_val}";\n')
        break
with open(path, 'w') as f:
    f.writelines(lines)
PYEOF
    fi
    success "Password hash written to configuration.nix"
  fi

  git -C "$REPO_DIR" add "$host_dir/"
}

#===========================
# Phase 7: Disko
#===========================

phase_partition() {
  [[ "$FEAT_ENCRYPTION" == "true" ]] && luks_password_file > /dev/null
  echo ""

  # shellcheck disable=SC2054  # comma is disko syntax, not array separator
  local disko_args=(--mode destroy,format,mount --flake "$REPO_DIR#$HOST" --yes-wipe-all-disks)

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

  # Scale build parallelism to available RAM (~4 GB per job, min 1)
  # Uses MemAvailable (not MemTotal) so live ISO overhead is accounted for
  local avail_gb max_jobs
  avail_gb=$(awk '/^MemAvailable:/{printf "%d", $2/1024/1024}' /proc/meminfo)
  max_jobs=$(( avail_gb / 4 ))
  (( max_jobs < 1 )) && max_jobs=1
  echo ""
  success "RAM available: ${avail_gb} GB — using --max-jobs ${max_jobs}"
  echo ""

  [[ "$FEAT_ENCRYPTION" == "true" ]] && luks_password_file > /dev/null

  info "Generating hardware configuration..."
  echo ""
  nixos-generate-config --root /mnt --show-hardware-config > "$host_dir/hardware-configuration.generated.nix"
  nix flake lock "$REPO_DIR"
  git -C "$REPO_DIR" add "$host_dir/hardware-configuration.generated.nix" "$REPO_DIR/flake.lock"
  success "Hardware configuration generated"
  echo ""

  # Redirect nix temp/build dirs to /mnt so they land on disk, not the live ISO tmpfs
  mkdir -p /mnt/tmp
  export TMPDIR=/mnt/tmp

  if [[ "$FEAT_SECURE_BOOT" == "true" ]]; then
    # Disable lanzaboote for the install — keys don't exist yet.
    # secure-boot-init handles everything after first boot.
    local override_nix="$host_dir/secure-boot-install-override.nix"
    printf '{ lib, ... }: { features.secureBoot.enable = lib.mkForce false; }\n' > "$override_nix"
    sed -i "/imports = \[/a\\    .\/secure-boot-install-override.nix" "$host_dir/configuration.nix"
    git -C "$REPO_DIR" add "$override_nix" "$host_dir/configuration.nix"

    local install_ok=true
    nixos-install --flake "$REPO_DIR#$HOST" --no-root-password --max-jobs "$max_jobs" \
      || install_ok=false

    sed -i '/secure-boot-install-override\.nix/d' "$host_dir/configuration.nix"
    rm -f "$override_nix"
    git -C "$REPO_DIR" add "$host_dir/configuration.nix"
    git -C "$REPO_DIR" rm --cached "$override_nix" 2>/dev/null || true

    [[ "$install_ok" == true ]] || error "nixos-install failed. Check the output above."
  else
    if ! nixos-install --flake "$REPO_DIR#$HOST" --no-root-password --max-jobs "$max_jobs"; then
      error "nixos-install failed. Check the output above."
    fi
  fi

  success "NixOS installed"
}

#===========================
# Phase 9: Post-Install
#===========================

setup_ssh() {
  AGE_KEY="$(nix-shell -p ssh-to-age --run "ssh-to-age -private-key -i $(printf '%q' "$SSH_KEY_FILE")")"

  local ssh_dir="/mnt/home/$CONFIG_USERNAME/.ssh"
  mkdir -p "$ssh_dir"
  cp "$SSH_KEY_FILE" "$ssh_dir/id_ed25519"
  ssh-keygen -y -f "$SSH_KEY_FILE" > "$ssh_dir/id_ed25519.pub"
  chmod 700 "$ssh_dir"
  chmod 600 "$ssh_dir/id_ed25519"
  chmod 644 "$ssh_dir/id_ed25519.pub"

  # Clean up temp file if key was pasted (not a persistent path)
  [[ -z "$SSH_KEY" ]] && rm -f "$SSH_KEY_FILE"

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
  install -m 600 /dev/null "$oath_file"
  echo "HOTP/T30/6 $CONFIG_USERNAME - $secret_hex" > "$oath_file"

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


setup_tpm() {
  # TPM hardware present?
  [[ -c /dev/tpmrm0 ]] || { warn "No TPM2 device found, skipping."; return 1; }

  # systemd-cryptenroll available?
  if ! command -v systemd-cryptenroll &>/dev/null; then
    warn "systemd-cryptenroll not available, skipping TPM enrollment."
    return 1
  fi

  local password_file
  password_file="$(luks_password_file)"

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
  save_state
}


copy_config() {
  local dest="/mnt/home/$CONFIG_USERNAME/repos/nix"
  if [[ ! -d "$dest" ]]; then
    mkdir -p "/mnt/home/$CONFIG_USERNAME/repos"

    # Stage all local changes (stateVersion, hardware config, password hash) so
    # nix eval on the installed system sees them immediately. Committing is left
    # to the user — the installer does not create commits on their behalf.
    git -C "$REPO_DIR" add --all

    # Copy full repo including .git so the installed system has history, remote
    # tracking, and can run git pull / nixos-rebuild for upgrades.
    cp -a "$REPO_DIR" "$dest"
    success "Config copied to ~/repos/nix"
  fi
}

phase_post_install() {
  echo ""
  setup_ssh
  setup_sops

  if [[ "$FEAT_TOTP" == "true" ]]; then
    local oath_file="/mnt${PERSIST_PREFIX}/etc/users.oath"
    if [[ -f "$oath_file" ]]; then
      success "TOTP already configured (cached)"
    elif [[ "$SKIP_TOTP" == "true" || "$YES" == "true" ]]; then
      warn "TOTP setup skipped. Run 'totp-init' after first boot."
    elif ! setup_totp; then
      warn "TOTP setup failed. Run 'totp-init' after first boot."
    fi
  fi

  if [[ "$FEAT_ENCRYPTION" == "true" && ${#LUKS_DEVICES[@]} -gt 0 ]]; then
    if [[ "$FEAT_YUBIKEY_LUKS" != "true" ]]; then
      if [[ "$FEAT_SECURE_BOOT" == "true" ]]; then
        # TPM PCR 7 measures Secure Boot state — enrolling now (Secure Boot OFF) would
        # produce a seal that breaks once Secure Boot is enabled after secure-boot-init.
        # Defer to first boot, after Secure Boot is fully set up.
        true
      elif ! setup_tpm; then
        warn "TPM enrollment skipped. Run 'sudo tpm-luks-init' after first boot."
      fi
    fi
  fi

  if ! copy_config; then
    warn "Config copy failed. Clone the repo manually after boot."
  fi

  echo ""
  info "Fixing home directory ownership..."
  echo ""
  nixos-enter --root /mnt -c "chown -R $CONFIG_USERNAME:users /home/$CONFIG_USERNAME"
  success "Ownership fixed"
}

#===========================
# Phase 10: Done
#===========================

phase_complete() {
  # Collect any post-boot tasks so we can show them in one place.
  # Order matters: Secure Boot before TPM (PCR 7 seals against SB state).
  local post_boot_tasks=()
  local tpm_deferred=false

  # Build post-boot task list. Order matters: Secure Boot must run before TPM
  # because PCR 7 seals against the active Secure Boot state.
  local oath_file="/mnt${PERSIST_PREFIX}/etc/users.oath"

  [[ "$FEAT_SECURE_BOOT" == "true" ]] && \
    post_boot_tasks+=("secure-boot-init    — sign boot files and enroll Secure Boot keys")

  [[ "$FEAT_YUBIKEY_LUKS" == "true" && "$FEAT_ENCRYPTION" == "true" ]] && \
    post_boot_tasks+=("yubikey-luks-init   — enroll YubiKey FIDO2 for LUKS unlock at boot")

  [[ "$FEAT_YUBIKEY" == "true" ]] && \
    post_boot_tasks+=("yubikey-init        — register YubiKey for sudo / SSH")

  # TOTP: only shown when not already configured (skipped via --skip-totp or -y)
  [[ "$FEAT_TOTP" == "true" && ! -f "$oath_file" ]] && \
    post_boot_tasks+=("totp-init           — configure TOTP 2FA for sudo / SSH")

  # TPM: deferred when Secure Boot is enabled so the seal is made against the
  # final SB state (PCR 7). Enrolling before SB is active produces a broken seal.
  if [[ "$TPM_ENROLLED" != "true" && "$FEAT_ENCRYPTION" == "true" && \
        "$FEAT_YUBIKEY_LUKS" != "true" && ${#LUKS_DEVICES[@]} -gt 0 ]]; then
    tpm_deferred=true
    post_boot_tasks+=("tpm-luks-init       — enroll TPM2 for automatic LUKS unlock at boot")
  fi

  # ASUS board detection for Secure Boot instructions
  local board_vendor sys_vendor is_asus=false
  board_vendor="$(cat /sys/class/dmi/id/board_vendor 2>/dev/null || true)"
  sys_vendor="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
  if [[ "$board_vendor" == *"ASUSTeK"* || "$board_vendor" == *"ASUS"* || \
        "$sys_vendor" == *"ASUSTeK"* || "$sys_vendor" == *"ASUS"* ]]; then
    is_asus=true
  fi

  echo ""
  echo -e "${BOLD}============================================${RESET}"
  echo -e "${GREEN}${BOLD}  Installation complete!${RESET}"
  echo -e "${BOLD}============================================${RESET}"

  # ---- What was set up ----
  echo ""
  echo -e "  ${BOLD}What was set up:${RESET}"
  echo ""
  echo -e "    NixOS installed for ${BOLD}$HOST${RESET} (${CONFIG_USERNAME})"
  if [[ "$FEAT_ENCRYPTION" == "true" ]]; then
    if [[ "$TPM_ENROLLED" == "true" ]]; then
      echo -e "    Disk encryption:  ${GREEN}LUKS + TPM2 auto-unlock${RESET}  ${DIM}(password fallback works)${RESET}"
    elif [[ "$FEAT_YUBIKEY_LUKS" == "true" ]]; then
      echo -e "    Disk encryption:  ${GREEN}LUKS${RESET}  ${DIM}(YubiKey FIDO2 enrollment pending — password at boot until then)${RESET}"
    elif [[ "$tpm_deferred" == "true" ]]; then
      echo -e "    Disk encryption:  ${GREEN}LUKS${RESET}  ${DIM}(TPM2 enrollment pending — password at boot until then)${RESET}"
    else
      echo -e "    Disk encryption:  ${GREEN}LUKS${RESET}  ${DIM}(password required at boot)${RESET}"
    fi
  fi
  if [[ "$FEAT_TOTP" == "true" ]]; then
    echo -e "    TOTP 2FA:         ${GREEN}configured${RESET}  ${DIM}(use your authenticator app for sudo/SSH)${RESET}"
  fi
  echo -e "    SSH key:          ${GREEN}installed${RESET}"
  echo -e "    SOPS age key:     ${GREEN}installed${RESET}"

  # ---- What to do after first boot ----
  if [[ ${#post_boot_tasks[@]} -gt 0 ]]; then
    echo ""
    echo -e "  ${BOLD}${YELLOW}After first boot, run these commands:${RESET}"
    echo ""
    local i=1
    for task in "${post_boot_tasks[@]}"; do
      local cmd="${task%%—*}"
      local desc="${task#*—}"
      echo -e "    ${BOLD}$((i++)).${RESET} ${BOLD}${cmd}${RESET} ${DIM}—${desc}${RESET}"
    done
    echo ""
    if [[ "$tpm_deferred" == "true" && "$FEAT_SECURE_BOOT" == "true" ]]; then
      echo -e "    ${DIM}Run secure-boot-init first — TPM enrollment seals against the active${RESET}"
      echo -e "    ${DIM}Secure Boot state (PCR 7). Wrong order = broken auto-unlock.${RESET}"
    else
      echo -e "    ${DIM}Until enrolled: LUKS uses password, sudo uses password fallback.${RESET}"
    fi
  fi

  # ---- Secure Boot UEFI instructions ----
  if [[ "$FEAT_SECURE_BOOT" == "true" ]]; then
    echo ""
    echo -e "  ${BOLD}Secure Boot — UEFI steps before running secure-boot-init:${RESET}"
    echo ""
    echo -e "    ${DIM}NixOS will boot normally with Secure Boot OFF until you complete these steps.${RESET}"
    echo ""
    if [[ "$is_asus" == "true" ]]; then
      echo -e "    ${YELLOW}! ASUS board — special Setup Mode procedure required.${RESET}"
      echo ""
      echo -e "    ${BOLD}Step A${RESET} — In UEFI (Boot → Secure Boot):"
      echo -e "      OS Type:          ${BOLD}Other OS${RESET}"
      echo -e "      Secure Boot Mode: ${BOLD}Custom${RESET}"
      echo -e "      Key Management:   ${BOLD}Clear Secure Boot Keys${RESET}"
      echo -e "      ${DIM}(ASUS does not enter Setup Mode automatically — key deletion is required)${RESET}"
      echo ""
      echo -e "    ${BOLD}Step B${RESET} — Save, reboot into NixOS and run ${BOLD}secure-boot-init${RESET}"
      echo ""
      echo -e "    ${BOLD}Step C${RESET} — In UEFI: activate Secure Boot:"
      echo -e "      Secure Boot: ${BOLD}Enabled${RESET}"
      echo -e "      ${DIM}→ Secure Boot state will show: On${RESET}"
    else
      echo -e "    ${BOLD}Step A${RESET} — In UEFI: enter Setup Mode:"
      echo -e "      Disable Secure Boot"
      echo -e "      Enable ${BOLD}Setup Mode${RESET}  ${DIM}(or 'Reset to Setup Mode' — clears existing keys)${RESET}"
      echo -e "      Save and reboot into NixOS"
      echo ""
      echo -e "    ${BOLD}Step B${RESET} — Run ${BOLD}secure-boot-init${RESET}"
      echo -e "      ${DIM}Generates keys, rebuilds with lanzaboote, enrolls into firmware.${RESET}"
      echo ""
      echo -e "    ${BOLD}Step C${RESET} — In UEFI: enable ${BOLD}Secure Boot${RESET}"
      echo -e "      ${DIM}Then run secure-boot-init once more to verify all files are signed.${RESET}"
    fi
  fi

  echo ""
  echo -e "${BOLD}============================================${RESET}"
  echo ""

  # ---- Reboot prompt ----
  if [[ "$YES" != true ]]; then
    if [[ "$FEAT_SECURE_BOOT" == "true" ]]; then
      read -rp "    Reboot into UEFI firmware setup now? [Y/n]: " confirm
      if [[ ! "${confirm:-}" =~ ^[nN]$ ]]; then
        systemctl reboot --firmware-setup
      else
        echo "    Reboot manually when ready."
      fi
    else
      read -rp "    Reboot now? [Y/n]: " confirm
      [[ "${confirm:-}" =~ ^[nN]$ ]] || reboot
    fi
  fi
  echo ""
}

#===========================
# Pending Setup Check
#===========================

# Shows which post-install steps still need to be done.
# Used both on the upgrade entry screen and after a successful upgrade.
show_pending_setup() {
  local json
  json=$(nix eval --json "$REPO_DIR#nixosConfigurations.${HOST}.config" --apply '
    cfg: {
      secureBoot    = cfg.features.secureBoot.enable;
      yubikey       = cfg.features.auth.yubikey.enable;
      yubikeyLuks   = cfg.features.encryption.unlockMethod == "yubikey";
      totp          = cfg.features.auth.totp.enable;
      encryption    = cfg.features.encryption.enable;
      persistPrefix = cfg.features.impermanence.persistPrefix;
    }
  ' 2>/dev/null) || json="{}"

  local feat_sb feat_yubikey feat_yubikey_luks feat_totp feat_enc persist_prefix
  feat_sb=$(echo "$json"           | jq -r '.secureBoot    // false')
  feat_yubikey=$(echo "$json"      | jq -r '.yubikey       // false')
  feat_yubikey_luks=$(echo "$json" | jq -r '.yubikeyLuks   // false')
  feat_totp=$(echo "$json"         | jq -r '.totp          // false')
  feat_enc=$(echo "$json"          | jq -r '.encryption    // false')
  persist_prefix=$(echo "$json"    | jq -r '.persistPrefix // ""')

  # Live state checks
  local sb_active=false yubikey_luks_enrolled=false yubikey_pam_enrolled=false totp_enrolled=false
  local invoking_username="${SUDO_USER:-$USER}"

  if [[ "$feat_sb" == "true" ]]; then
    local sb_state
    sb_state=$(bootctl status 2>/dev/null | awk '/Secure Boot:/{print $3}')
    [[ "$sb_state" == "enabled" ]] && sb_active=true
  fi
  if [[ "$feat_yubikey_luks" == "true" && "$feat_enc" == "true" ]]; then
    # Find the underlying LUKS block device by looking for the parent of the
    # first crypt device — systemd-cryptenroll needs the raw partition, not /dev/mapper/...
    local first_dev
    first_dev=$(lsblk -rno NAME,TYPE,PKNAME | awk '$2=="crypt" && $3!="" {print "/dev/"$3; exit}')
    if [[ -n "$first_dev" ]] && systemd-cryptenroll "$first_dev" 2>/dev/null | grep -q "fido2"; then
      yubikey_luks_enrolled=true
    fi
  fi
  if [[ "$feat_yubikey" == "true" ]]; then
    local u2f_file="${persist_prefix}/etc/u2f_mappings"
    [[ -f "$u2f_file" ]] && grep -q "^${invoking_username}:" "$u2f_file" 2>/dev/null && yubikey_pam_enrolled=true
  fi
  if [[ "$feat_totp" == "true" ]]; then
    local oath_file="${persist_prefix}/etc/users.oath"
    [[ -f "$oath_file" ]] && grep -q "^HOTP.*${invoking_username}" "$oath_file" 2>/dev/null && totp_enrolled=true
  fi

  # Build pending task list
  local pending=()

  [[ "$feat_sb" == "true"           && "$sb_active" != "true"            ]] && \
    pending+=("secure-boot-init    — sign boot files and enroll Secure Boot keys into firmware")

  [[ "$feat_yubikey_luks" == "true" && "$yubikey_luks_enrolled" != "true" ]] && \
    pending+=("yubikey-luks-init   — enroll YubiKey FIDO2 for automatic disk unlock at boot")

  [[ "$feat_yubikey" == "true"      && "$yubikey_pam_enrolled" != "true"  ]] && \
    pending+=("yubikey-init        — register YubiKey for sudo and SSH authentication")

  [[ "$feat_totp" == "true"         && "$totp_enrolled" != "true"         ]] && \
    pending+=("totp-init           — set up TOTP two-factor authentication for sudo and SSH")

  if [[ ${#pending[@]} -eq 0 ]]; then
    success "All features are fully set up."
  else
    echo -e "  ${BOLD}${YELLOW}Pending setup:${RESET}"
    echo ""
    local i=1
    for task in "${pending[@]}"; do
      local cmd="${task%%—*}"
      local desc="${task#*—}"
      echo -e "    ${BOLD}$((i++)).${RESET} ${BOLD}${cmd}${RESET} ${DIM}—${desc}${RESET}"
    done
    echo ""
    echo -e "    ${DIM}Each script is interactive and guides you through the process step by step.${RESET}"
  fi
}

#===========================
# Phase Upgrade (installed system)
#===========================

phase_upgrade() {
  # Mirror what the auto-upgrade service does:
  # 1. Reset flake.lock to HEAD (discard local experiments)
  # 2. Pull latest changes from remote
  # 3. nixos-rebuild switch (activate immediately, unlike the service which uses boot)

  local invoking_user="${SUDO_USER:-$USER}"

  info "Syncing repository..."
  echo ""
  if git -C "$REPO_DIR" remote get-url origin &>/dev/null; then
    sudo -u "$invoking_user" git -C "$REPO_DIR" checkout flake.lock
    sudo -u "$invoking_user" git -C "$REPO_DIR" pull --ff-only
    success "Repository up to date"
  else
    warn "No git remote configured — skipping pull"
  fi
  echo ""

  info "Rebuilding system..."
  echo ""

  # Stop the auto-upgrade service while we build to avoid concurrent Nix store
  # access which can cause "getting attributes of path" errors mid-build.
  # Stop both the timer and the service to prevent concurrent Nix store access.
  # If the service is actively building, wait for it to finish first.
  local upgrade_was_active=false
  if systemctl is-active --quiet nixos-upgrade.timer 2>/dev/null \
      || systemctl is-active --quiet nixos-upgrade.service 2>/dev/null; then
    upgrade_was_active=true
    if systemctl is-active --quiet nixos-upgrade.service 2>/dev/null; then
      info "nixos-upgrade.service is running — waiting for it to finish..."
      systemctl stop nixos-upgrade.service 2>/dev/null || true
    fi
    info "Stopping nixos-upgrade.timer..."
    systemctl stop nixos-upgrade.timer 2>/dev/null || true
    info "Verifying Nix store integrity..."
    nix-store --verify --repair 2>/dev/null || true
  fi

  local avail_gb max_jobs
  avail_gb=$(awk '/^MemAvailable:/{printf "%d", $2/1024/1024}' /proc/meminfo)
  max_jobs=$(( avail_gb / 4 ))
  (( max_jobs < 1 )) && max_jobs=1
  success "RAM available: ${avail_gb} GB — using --max-jobs ${max_jobs}"
  echo ""

  # lanzaboote requires /var/lib/sbctl/keys to exist at build time.
  # If secure-boot-init hasn't run yet, disable lanzaboote for this rebuild
  # so the system can still be upgraded. secure-boot-init will re-enable it.
  local sb_keys_exist=false
  [[ -f /var/lib/sbctl/keys/db/db.pem && -f /var/lib/sbctl/keys/db/db.key ]] && sb_keys_exist=true

  # Check if secureBoot is enabled by grepping the host config directly —
  # more reliable than nix eval which can fail for various reasons on an
  # installed system (missing flake registry, network, etc.)
  local sb_config_enabled=false
  local host_config="$REPO_DIR/hosts/$HOST/configuration.nix"
  if grep -q 'secureBoot\.enable\s*=\s*true' "$host_config" 2>/dev/null; then
    sb_config_enabled=true
  fi

  if [[ "$sb_config_enabled" == "true" && "$sb_keys_exist" != "true" ]]; then
    warn "Secure Boot keys not yet generated — disabling lanzaboote for this rebuild."
    echo ""
    local host_dir="$REPO_DIR/hosts/$HOST"
    local override_nix="$host_dir/secure-boot-upgrade-override.nix"
    printf '{ lib, ... }: { features.secureBoot.enable = lib.mkForce false; }\n' > "$override_nix"
    sed -i "/imports = \[/a\\    .\/secure-boot-upgrade-override.nix" "$host_dir/configuration.nix"
    git -C "$REPO_DIR" add "$override_nix" "$host_dir/configuration.nix"

    local rebuild_ok=true
    nixos-rebuild switch --flake "$REPO_DIR#$HOST" --max-jobs "$max_jobs" ${REPAIR:+--repair} || rebuild_ok=false

    sed -i '/secure-boot-upgrade-override\.nix/d' "$host_dir/configuration.nix"
    rm -f "$override_nix"
    git -C "$REPO_DIR" rm --cached "$override_nix" 2>/dev/null || true
    git -C "$REPO_DIR" add "$host_dir/configuration.nix"

    if [[ "$upgrade_was_active" == "true" ]]; then
      info "Restarting nixos-upgrade.timer..."
      systemctl start nixos-upgrade.timer
    fi
    [[ "$rebuild_ok" == true ]] || error "nixos-rebuild failed. Check the output above."
  else
    nixos-rebuild switch --flake "$REPO_DIR#$HOST" --max-jobs "$max_jobs" ${REPAIR:+--repair} \
      || { if [[ "$upgrade_was_active" == "true" ]]; then info "Restarting nixos-upgrade.timer..."; systemctl start nixos-upgrade.timer; fi; error "nixos-rebuild failed. Check the output above."; }
  fi

  if [[ "$upgrade_was_active" == "true" ]]; then
    info "Restarting nixos-upgrade.timer..."
    systemctl start nixos-upgrade.timer
  fi

  echo ""
  success "System upgraded."

  [[ "$QUIET_UPGRADE" == "true" ]] && return

  echo ""
  echo -e "${BOLD}============================================${RESET}"
  echo -e "${GREEN}${BOLD}  Upgrade complete!${RESET}"
  echo -e "${BOLD}============================================${RESET}"
  echo ""

  show_pending_setup

  echo ""
  echo -e "${BOLD}============================================${RESET}"
  echo ""
}

#===========================
# Main
#===========================

main() {
  load_state
  phase_validate
  phase_select_host

  # On an installed system: always upgrade — step flags are ignored.
  if [[ "$IS_LIVE" != true ]]; then
    local sb_enabled=false
    grep -q 'secureBoot\.enable\s*=\s*true' "$REPO_DIR/hosts/$HOST/configuration.nix" 2>/dev/null && sb_enabled=true

    echo -e "    ${DIM}Pulls the latest configuration from git and rebuilds the system.${RESET}"
    echo -e "    ${DIM}Activates immediately — no reboot required.${RESET}"
    echo ""

    if [[ "$YES" == true ]]; then
      phase_upgrade
      exit 0
    fi

    local confirm
    read -rp "Run upgrade now? [Y/n]: " confirm
    echo ""
    [[ ! "$confirm" =~ ^[nN]$ ]] || exit 0
    phase_upgrade
    exit 0
  fi

  # shellcheck disable=SC2046
  echo -e "    Steps: ${BOLD}$(printf '%s ' \
    $([[ "$DO_FORMAT" == true ]] && echo "format") \
    $([[ "$DO_INSTALL" == true ]] && echo "install") \
    $([[ "$DO_POST_INSTALL" == true ]] && echo "post-install"))${RESET}"
  echo ""

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
}

main
