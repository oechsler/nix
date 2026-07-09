# TPM Enrollment for LUKS Auto-Unlock
#
# Provides `tpm-luks-init` script to enroll/re-enroll/wipe TPM2 keys
# for all LUKS partitions. Active when features.encryption.unlockMethod = "tpm2".
#
# Usage: sudo tpm-luks-init
# PCR policy: 0+7 (firmware + Secure Boot state).

{
  config,
  lib,
  pkgs,
  ...
}:

let
  luksDevices = config.boot.initrd.luks.devices;
  deviceList = lib.concatStringsSep " " (map (d: d.device) (lib.attrValues luksDevices));

  tpm-luks-init = pkgs.writeShellApplication {
    name = "tpm-luks-init";
    runtimeInputs = with pkgs; [
      systemd
      coreutils
    ];
    text = ''
      if [[ $EUID -ne 0 ]]; then
        exec sudo "$0" "$@"
      fi

      RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m'
      BLUE='\033[0;34m' BOLD='\033[1m' DIM='\033[2m' RESET='\033[0m'

      info()    { echo -e "''${BLUE}==>''${RESET} ''${BOLD}$*''${RESET}"; }
      success() { echo -e "    ''${GREEN}✓''${RESET} $*"; }
      warn()    { echo -e "    ''${YELLOW}!''${RESET} $*"; }
      error()   { echo -e "''${RED}Error:''${RESET} $*" >&2; exit 1; }
      step()    { echo -e "\n''${BOLD}[$1/$2]''${RESET} $3"; }

      echo ""
      echo -e "''${BOLD}TPM2 LUKS Setup''${RESET}"
      echo -e "''${DIM}Enroll TPM2 chip for automatic disk unlock at boot''${RESET}"
      echo ""

      TPM_DEVICE="/dev/tpmrm0"
      DEVICES=(${deviceList})
      PCRS="0+7"

      if [[ ! -c "$TPM_DEVICE" ]]; then
        error "No TPM2 device found. Make sure TPM2 is enabled in UEFI/BIOS."
      fi

      if [[ ''${#DEVICES[@]} -eq 0 ]]; then
        error "No LUKS devices found in NixOS config."
      fi

      #--- Show status ---

      info "LUKS devices (from NixOS config):"
      echo ""
      for dev in "''${DEVICES[@]}"; do
        NAME=$(basename "$dev")
        # Check if TPM2 slot is enrolled
        if systemd-cryptenroll "$dev" 2>/dev/null | grep -q "tpm2"; then
          STATUS="TPM2 enrolled"
        else
          STATUS="no TPM2 enrolled"
        fi
        echo "  $NAME ($dev) — $STATUS"
      done

      #--- Menu ---

      # Check if any device already has a TPM2 slot (for contextual menu label)
      TPM2_EXISTS=false
      for dev in "''${DEVICES[@]}"; do
        systemd-cryptenroll "$dev" 2>/dev/null | grep -q "tpm2" && TPM2_EXISTS=true && break
      done

      echo ""
      if [[ "$TPM2_EXISTS" == "true" ]]; then
        echo "  [e] Re-enroll TPM2 (wipes existing TPM2 slots first)"
      else
        echo "  [e] Enroll TPM2"
      fi
      echo "  [w] Wipe TPM2 slots"
      echo "  [q] Quit"
      echo ""
      read -rp "Choice: " CHOICE

      case "$CHOICE" in
        e|E)
          echo ""
          read -rsp "Enter LUKS password: " PASSWORD
          echo ""
          PASS_FILE="$(mktemp)"
          trap 'rm -f "$PASS_FILE"' EXIT
          printf '%s' "$PASSWORD" > "$PASS_FILE"
          chmod 600 "$PASS_FILE"
          ENROLL_OK=true
          for dev in "''${DEVICES[@]}"; do
            if systemd-cryptenroll "$dev" 2>/dev/null | grep -q "tpm2"; then
              echo -e "    ''${DIM}$(basename "$dev"):''${RESET} wiping existing TPM2 slot..."
              systemd-cryptenroll "$dev" --wipe-slot=tpm2 || true
            fi
            echo -e "    ''${DIM}$(basename "$dev"):''${RESET} enrolling..."
            if systemd-cryptenroll "$dev" --tpm2-device=auto --tpm2-pcrs="$PCRS" --unlock-key-file="$PASS_FILE"; then
              success "$(basename "$dev"): enrolled"
            else
              warn "$(basename "$dev"): FAILED"
              ENROLL_OK=false
            fi
          done
          if [[ "$ENROLL_OK" == "true" ]]; then
            echo ""
            success "TPM2 enrolled."
            echo ""
            echo -e "  ''${DIM}Your disk will unlock automatically at boot as long as the system''${RESET}"
            echo -e "  ''${DIM}firmware and Secure Boot state have not changed.''${RESET}"
          else
            echo ""
            error "Enrollment failed on one or more devices. Check the output above."
          fi
          ;;
        w|W)
          echo ""
          read -rp "Wipe TPM2 from all devices? [y/N] " CONFIRM
          if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
            echo "Aborted."
            exit 0
          fi
          for dev in "''${DEVICES[@]}"; do
            if systemd-cryptenroll "$dev" 2>/dev/null | grep -q "tpm2"; then
              echo -e "    ''${DIM}$(basename "$dev"):''${RESET} wiping TPM2 slot..."
              systemd-cryptenroll "$dev" --wipe-slot=tpm2 || true
            else
              warn "$(basename "$dev"): no TPM2 slot, skipping"
            fi
          done
          echo ""
          success "TPM2 slots wiped. Disk will require password at next boot."
          ;;
        *)
          echo "Aborted."
          exit 0
          ;;
      esac
    '';
  };
in
{
  config =
    lib.mkIf (config.features.encryption.enable && config.features.encryption.unlockMethod == "tpm2")
      {
        environment.systemPackages = [ tpm-luks-init ];
      };
}
