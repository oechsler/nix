# shellcheck shell=bash
# shellcheck disable=SC2034
# Shared arguments, paths, feature state, and cleanup.

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
INSTALLER_ISO="${INSTALLER_ISO:-false}"
REPO_URL="${REPO_URL:-https://github.com/oechsler/nix.git}"
REPO_REMOTE_URL="https://git.at.oechsler.it/samuel/nix.git"
REPO_DIR="$SCRIPT_DIR"

# When invoked via PATH, resolve the repo from the upgrade unit.
if [[ ! -f "$REPO_DIR/flake.nix" ]]; then
  if command -v systemctl >/dev/null && command -v grep >/dev/null &&
    command -v awk >/dev/null && command -v sed >/dev/null; then
    REPO_DIR=$(systemctl show nixos-upgrade.service --property=ExecStart 2>/dev/null |
      grep -o -- '--flake [^ ]*' | awk '{print $2}' | sed 's/#.*//' || true)
  else
    REPO_DIR=""
  fi
  if [[ -z "$REPO_DIR" || ! -f "$REPO_DIR/flake.nix" ]]; then
    if command -v getent >/dev/null && command -v cut >/dev/null; then
      USER_HOME="$(getent passwd "${SUDO_USER:-${USER:-root}}" | cut -d: -f6)"
    else
      USER_HOME="${HOME:-}"
    fi
    REPO_DIR="${USER_HOME:-${HOME:-/root}}/repos/nix"
  fi
fi

STATE_DIR="/var/lib/nixos-install"
STATE_FILE="$STATE_DIR/state.env"
LUKS_PASSWORD_FILE=""
INSTALL_SUCCESS=false

SSH_KEY_FILE=""
SSH_KEY_CONTENT=""
AGE_KEY=""
USER_PASSWORD_HASH=""
IS_LIVE=false
DO_MOUNT=false
SECURE_BOOT_OVERRIDE_FILE=""
SECURE_BOOT_CONFIG_FILE=""

cleanup() {
  [[ -z "$LUKS_PASSWORD_FILE" ]] || rm -f -- "$LUKS_PASSWORD_FILE"
  if [[ -n "$SECURE_BOOT_CONFIG_FILE" ]]; then
    sed -i '/secure-boot-\(install\|upgrade\)-override\.nix/d' "$SECURE_BOOT_CONFIG_FILE" 2>/dev/null || true
  fi
  [[ -z "$SECURE_BOOT_OVERRIDE_FILE" ]] || rm -f -- "$SECURE_BOOT_OVERRIDE_FILE"
  [[ "$INSTALL_SUCCESS" == true ]] && rm -f -- "$STATE_FILE"
}

trap cleanup EXIT
trap 'exit 130' HUP INT TERM

load_state() {
  if [[ -f "$STATE_FILE" ]]; then
    echo ""
    info "Resuming previous session"
    echo ""
    local cli_host="$HOST" cli_ssh="$SSH_KEY" cli_luks="$LUKS_PASSWORD"
    # shellcheck source=/dev/null
    source "$STATE_FILE"
    [[ -n "$cli_host" ]] && HOST="$cli_host"
    [[ -n "$cli_luks" ]] && LUKS_PASSWORD="$cli_luks"
    if [[ -n "$cli_ssh" ]]; then
      SSH_KEY="$cli_ssh"
      SSH_KEY_FILE=""
    elif [[ -n "${SSH_KEY_CONTENT:-}" ]]; then
      SSH_KEY_FILE="$(mktemp)"
      printf '%s\n' "$SSH_KEY_CONTENT" >"$SSH_KEY_FILE"
      chmod 600 "$SSH_KEY_FILE"
    fi
    success "Loaded: host=$HOST"
    echo ""
  fi
}

save_state() {
  [[ "$DRY_RUN" == true ]] && return 0
  local temporary
  temporary=$(mktemp "$STATE_DIR/state.env.XXXXXX")
  trap 'rm -f "$temporary"' RETURN
  {
    printf 'HOST=%q\n' "$HOST"
    printf 'LUKS_PASSWORD=%q\n' "${LUKS_PASSWORD:-}"
    printf 'USER_PASSWORD_HASH=%q\n' "${USER_PASSWORD_HASH:-}"
    if [[ -n "${SSH_KEY_FILE:-}" && -f "$SSH_KEY_FILE" ]]; then
      printf 'SSH_KEY_CONTENT=%q\n' "$(<"$SSH_KEY_FILE")"
    else
      printf 'SSH_KEY_CONTENT=%q\n' "${SSH_KEY_CONTENT:-}"
    fi
    printf 'FEAT_ENCRYPTION=%q\n' "${FEAT_ENCRYPTION:-false}"
    printf 'FEAT_UNLOCK_METHOD=%q\n' "${FEAT_UNLOCK_METHOD:-}"
    printf 'FEAT_IMPERMANENCE=%q\n' "${FEAT_IMPERMANENCE:-false}"
    printf 'PERSIST_PREFIX=%q\n' "${PERSIST_PREFIX:-}"
    printf 'FEAT_TOTP=%q\n' "${FEAT_TOTP:-false}"
    printf 'FEAT_YUBIKEY=%q\n' "${FEAT_YUBIKEY:-false}"
    printf 'FEAT_YUBIKEY_LUKS=%q\n' "${FEAT_YUBIKEY_LUKS:-false}"
    printf 'FEAT_SECURE_BOOT=%q\n' "${FEAT_SECURE_BOOT:-false}"
    printf 'FEAT_DESKTOP=%q\n' "${FEAT_DESKTOP:-false}"
    printf 'FEAT_WM=%q\n' "${FEAT_WM:-}"
    printf 'FEAT_FORM_FACTOR=%q\n' "${FEAT_FORM_FACTOR:-}"
    printf 'FEAT_KERNEL=%q\n' "${FEAT_KERNEL:-}"
    printf 'FEAT_KERNEL_VERSION=%q\n' "${FEAT_KERNEL_VERSION:-}"
    printf 'FEAT_KEYBOARD=%q\n' "${FEAT_KEYBOARD:-}"
    printf 'FEAT_LANGUAGE=%q\n' "${FEAT_LANGUAGE:-}"
    printf 'CONFIG_USERNAME=%q\n' "${CONFIG_USERNAME:-}"
    printf 'CONFIG_PASSWORD_LOCKED=%q\n' "${CONFIG_PASSWORD_LOCKED:-false}"
    printf 'TPM_ENROLLED=%q\n' "${TPM_ENROLLED:-false}"
  } >"$temporary"
  chmod 600 "$temporary"
  mv "$temporary" "$STATE_FILE"
  trap - RETURN
}
