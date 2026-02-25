# TPM Enrollment for LUKS Auto-Unlock
#
# Provides `tpm-init` script to enroll/re-enroll/wipe TPM2 keys for all
# LUKS-encrypted partitions defined in boot.initrd.luks.devices.
#
# Configuration:
#   features.encryption.enable = true;  # Enables this module (default: true)
#
# Usage:
#   sudo tpm-init
#
# The script reads LUKS devices from the NixOS config at build time,
# so it automatically knows about all encrypted partitions.
#
# PCR policy: 0+7 (firmware measurement + Secure Boot state)
# Works with or without Secure Boot. If Secure Boot is enabled later,
# re-run `tpm-init` to re-enroll with the new PCR 7 value.
#
# See also: docs/INSTALL.md (TPM Unlock section)

{
  config,
  lib,
  pkgs,
  ...
}:

let
  luksDevices = config.boot.initrd.luks.devices;
  deviceList = lib.concatStringsSep " " (map (d: d.device) (lib.attrValues luksDevices));

  tpm-init = pkgs.writeShellApplication {
    name = "tpm-init";
    runtimeInputs = with pkgs; [
      systemd
      coreutils
    ];
    text = ''
      if [[ $EUID -ne 0 ]]; then
        exec sudo "$0" "$@"
      fi

      TPM_DEVICE="/dev/tpmrm0"
      DEVICES=(${deviceList})
      PCRS="0+7"

      if [[ ! -c "$TPM_DEVICE" ]]; then
        echo "Error: TPM2 device not found ($TPM_DEVICE)"
        echo "Make sure your system has a TPM2 chip and it's enabled in BIOS."
        exit 1
      fi

      if [[ ''${#DEVICES[@]} -eq 0 ]]; then
        echo "Error: No LUKS devices found in NixOS config."
        exit 1
      fi

      #--- Show status ---

      echo "LUKS devices (from NixOS config):"
      echo ""
      for dev in "''${DEVICES[@]}"; do
        NAME=$(basename "$dev")
        # Check if TPM2 slot is enrolled
        if systemd-cryptenroll "$dev" 2>/dev/null | grep -q "tpm2"; then
          STATUS="TPM2 enrolled"
        else
          STATUS="No TPM2"
        fi
        echo "  $NAME ($dev) — $STATUS"
      done

      #--- Menu ---

      echo ""
      echo "  [e] Enroll TPM2 (wipes existing slots first)"
      echo "  [w] Wipe TPM2 slots"
      echo "  [q] Quit"
      echo ""
      read -rp "Choice: " CHOICE

      case "$CHOICE" in
        e|E)
          echo ""
          read -rsp "LUKS password: " PASSWORD
          echo ""
          PASS_FILE="$(mktemp)"
          echo "$PASSWORD" > "$PASS_FILE"
          chmod 600 "$PASS_FILE"
          for dev in "''${DEVICES[@]}"; do
            if systemd-cryptenroll "$dev" 2>/dev/null | grep -q "tpm2"; then
              echo "Wiping existing TPM2 slot on $(basename "$dev")..."
              systemd-cryptenroll "$dev" --wipe-slot=tpm2 || true
            fi
            echo "Enrolling $(basename "$dev")..."
            if systemd-cryptenroll "$dev" --tpm2-device=auto --tpm2-pcrs="$PCRS" --unlock-key-file="$PASS_FILE"; then
              echo "  OK"
            else
              echo "  FAILED"
            fi
          done
          rm -f "$PASS_FILE"
          echo ""
          echo "Done."
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
              echo "Wiping TPM2 slot on $(basename "$dev")..."
              systemd-cryptenroll "$dev" --wipe-slot=tpm2 || true
            else
              echo "$(basename "$dev"): no TPM2 slot, skipping"
            fi
          done
          echo ""
          echo "Done. TPM2 slots wiped."
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
  config = lib.mkIf config.features.encryption.enable {
    environment.systemPackages = [ tpm-init ];
  };
}
