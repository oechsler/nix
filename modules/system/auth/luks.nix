# FIDO2 LUKS enrollment and initrd integration.

{
  config,
  lib,
  pkgs,
  ...
}:

let
  enabled = config.features.encryption.unlockMethod == "yubikey";
  devices = config.boot.initrd.luks.devices;
  deviceList = lib.escapeShellArgs (map (d: d.device) (lib.attrValues devices));
  yubikey-luks-init = pkgs.writeShellApplication {
    name = "yubikey-luks-init";
    runtimeInputs = with pkgs; [
      systemd
      gawk
      uutils-coreutils-noprefix
      sudo
    ];
    text = ''
      if [[ $EUID -ne 0 ]]; then exec sudo "$0" "$@"; fi
      DEVICES=(${deviceList})
      [[ ''${#DEVICES[@]} -gt 0 ]] || { echo "Error: No LUKS devices found in NixOS config." >&2; exit 1; }
      get_fido2_slots() { systemd-cryptenroll "$1" 2>/dev/null | awk '$2=="fido2"{print $1}'; }
      do_enroll() {
        read -rsp "Enter LUKS password: " PASSWORD; echo ""; PASS_FILE=$(mktemp); trap 'rm -f "$PASS_FILE"' EXIT
        printf '%s' "$PASSWORD" > "$PASS_FILE"; chmod 600 "$PASS_FILE"; ENROLL_OK=true
        for dev in "''${DEVICES[@]}"; do ATTEMPT=0; DEV_OK=false
          while [[ $ATTEMPT -lt 3 ]]; do ATTEMPT=$(( ATTEMPT + 1 ))
            if systemd-cryptenroll "$dev" --fido2-device=auto --fido2-with-client-pin=no --unlock-key-file="$PASS_FILE"; then DEV_OK=true; break; fi
          done
          [[ "$DEV_OK" == true ]] || ENROLL_OK=false
        done
        [[ "$ENROLL_OK" == true ]] || { echo "Error: Enrollment failed." >&2; exit 1; }
      }
      echo "LUKS devices (from NixOS config):"; for dev in "''${DEVICES[@]}"; do
        mapfile -t SLOTS < <(get_fido2_slots "$dev"); echo "  $(basename "$dev") ($dev) — ''${#SLOTS[@]} FIDO2 key(s) enrolled"
      done
      mapfile -t REF_SLOTS < <(get_fido2_slots "''${DEVICES[0]}"); SLOT_COUNT=''${#REF_SLOTS[@]}
      echo ""
      if [[ $SLOT_COUNT -eq 0 ]]; then
        echo "  [e] Enroll YubiKey"; echo "  [q] Quit"; echo ""; read -rp "Choice: " CHOICE
        case "$CHOICE" in e|E) do_enroll ;; *) echo "Aborted."; exit 0 ;; esac
      else
        echo "  [a] Add key"; echo "  [d] Delete key"; echo "  [q] Quit"; echo ""; read -rp "Choice: " CHOICE
        case "$CHOICE" in
          a|A) do_enroll ;;
          d|D)
            if [[ $SLOT_COUNT -eq 1 ]]; then
              read -rp "Delete the only enrolled key? [y/N] " CONFIRM
              [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]] || { echo "Aborted."; exit 0; }
              for dev in "''${DEVICES[@]}"; do systemd-cryptenroll "$dev" --wipe-slot=fido2 || true; done
            else
              for i in "''${!REF_SLOTS[@]}"; do echo "  [$((i+1))] slot ''${REF_SLOTS[$i]}"; done
              read -rp "Delete which key? (1-$SLOT_COUNT, 'a' for all) " DEL_CHOICE
              if [[ "$DEL_CHOICE" == "a" || "$DEL_CHOICE" == "A" ]]; then
                for dev in "''${DEVICES[@]}"; do systemd-cryptenroll "$dev" --wipe-slot=fido2 || true; done
              elif [[ "$DEL_CHOICE" =~ ^[0-9]+$ ]] && (( DEL_CHOICE >= 1 && DEL_CHOICE <= SLOT_COUNT )); then
                SLOT_TO_DEL="''${REF_SLOTS[$((DEL_CHOICE-1))]}"
                for dev in "''${DEVICES[@]}"; do systemd-cryptenroll "$dev" --wipe-slot="$SLOT_TO_DEL" || true; done
              else echo "Error: Invalid choice." >&2; exit 1; fi
            fi ;;
          *) echo "Aborted."; exit 0 ;;
        esac
      fi
    '';
  };
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = [ yubikey-luks-init ];
    boot.initrd.systemd = {
      enable = lib.mkDefault true;
      storePaths = [
        pkgs.pcsclite.lib
        pkgs.libfido2
        pkgs.uutils-coreutils-noprefix
      ];
      packages = [ pkgs.libfido2 ];
      services = {
        "fido2-yubikey-wait" = {
          description = "Wait for FIDO2 security token enumeration";
          unitConfig.DefaultDependencies = "no";
          after = [
            "systemd-udevd.service"
            "systemd-udev-trigger.service"
          ];
          wants = [
            "systemd-udevd.service"
            "systemd-udev-trigger.service"
          ];
          serviceConfig.Type = "oneshot";
          script = ''
            deadline=$((SECONDS + 6))
            while [ "$SECONDS" -lt "$deadline" ]; do
              for dev in /dev/hidraw*; do
                [ -e "$dev" ] || continue
                props="$(${pkgs.systemd}/bin/udevadm info --query=property --name="$dev" 2>/dev/null || true)"
                case "$props" in *ID_VENDOR_ID=1050*) exit 0 ;; esac
              done
              ${pkgs.uutils-coreutils-noprefix}/bin/sleep 0.2
            done
          '';
        };
        "systemd-udevd" = {
          overrideStrategy = "asDropin";
          serviceConfig.TimeoutStopSec = "2s";
        };
      }
      // lib.mapAttrs' (
        name: _:
        lib.nameValuePair "systemd-cryptsetup@${name}" {
          overrideStrategy = "asDropin";
          after = [ "fido2-yubikey-wait.service" ];
          wants = [ "fido2-yubikey-wait.service" ];
          serviceConfig.TimeoutStartSec = "infinity";
        }
      ) devices;
    };
  };
}
