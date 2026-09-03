# shellcheck shell=bash
# shellcheck disable=SC2034
# Command-line parsing and installer mode selection.

show_help() {
  cat <<'EOF'
NixOS Interactive Installer

Usage: install.sh [options]

Steps (combinable, default: all):
  --format              Partition and format disks (disko)
  --install             Install NixOS (nixos-install)
  --post-install        Post-install setup (SSH, SOPS, TOTP, TPM/FIDO2)

Options:
  --host HOST                Pre-select host configuration
  -s, --ssh-key PATH         Path to SSH private key
  -p, --luks-password PASS   LUKS disk encryption password
  --iso                      Use prebuilt system closure from the installer ISO
  --skip-totp                Skip TOTP setup (deferred to totp-init after first boot)
  --repair                   Verify/repair the Nix store before rebuilding
  --quiet                    Suppress upgrade prompts on installed systems
  -y, --yes                  Skip all confirmation prompts
  --dry-run                  Show summary and exit without making changes
  -h, --help                 Show this help

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

require_option_value() {
  [[ $# -ge 2 && -n "${2:-}" ]] || {
    echo "Option $1 requires a value." >&2
    exit 1
  }
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help) show_help ;;
      --host)
        require_option_value "$@"
        HOST="$2"
        shift 2
        ;;
      -s | --ssh-key)
        require_option_value "$@"
        SSH_KEY="$2"
        shift 2
        ;;
      -p | --luks-password)
        require_option_value "$@"
        LUKS_PASSWORD="$2"
        shift 2
        ;;
      --skip-totp)
        SKIP_TOTP=true
        shift
        ;;
      --quiet)
        QUIET_UPGRADE=true
        shift
        ;;
      --repair)
        REPAIR=true
        shift
        ;;
      -y | --yes)
        YES=true
        shift
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --format)
        DO_FORMAT=true
        shift
        ;;
      --install)
        DO_INSTALL=true
        shift
        ;;
      --post-install)
        DO_POST_INSTALL=true
        shift
        ;;
      --iso)
        INSTALLER_ISO=true
        shift
        ;;
      *)
        echo "Unknown option: $1" >&2
        echo "Run '$0 --help' for usage information." >&2
        exit 1
        ;;
    esac
  done

  ISO_MANIFEST="/etc/nixos-installer/manifest.json"
  if [[ -f "$ISO_MANIFEST" ]]; then
    INSTALLER_ISO=true
    REPO_DIR="/etc/nixos-installer/repo"
  fi
  if [[ "$INSTALLER_ISO" == true && ! -f "$ISO_MANIFEST" ]]; then
    echo "Installer ISO manifest not found: $ISO_MANIFEST" >&2
    exit 1
  fi
  if [[ "$DO_FORMAT" == false && "$DO_INSTALL" == false && "$DO_POST_INSTALL" == false ]]; then
    DO_FORMAT=true
    DO_INSTALL=true
    DO_POST_INSTALL=true
  fi
}
