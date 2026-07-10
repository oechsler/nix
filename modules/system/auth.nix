# Authentication & 2FA Configuration (PAM, LUKS, YubiKey, TOTP)
#
# This module configures all authentication layers: LUKS boot unlock, PAM services
# (login, sddm, sudo, sshd, etc.), and optionally YubiKey/TOTP.
#
# --- FLOWS ---
#
# The primary control is features.encryption.unlockMethod (see features.nix).
# YubiKey PAM/Tools are auto-enabled when unlockMethod = "yubikey".
# TOTP is always on by default and acts as fallback when YubiKey is also active.
#
#   unlockMethod = "yubikey";
#   → YubiKey FIDO2 LUKS unlock (touch only, no PIN — not supported by YubiKey).
#     YubiKey on sudo. TOTP fallback on sudo.
#     SDDM: password only (pam_gnome_keyring needs the login password).
#     SSH: YubiKey only (no password), publickey required.
#
#   unlockMethod = "tpm2";
#   → TPM2 LUKS auto-unlock. No YubiKey PAM unless auth.yubikey.enable overridden.
#     TOTP on sudo (primary). SDDM: password only. SSH: TOTP only.
#
#   unlockMethod = "password";
#   → Manual LUKS passphrase prompt at boot. Same as tpm2 for PAM flow.
#     Can be combined with desktop.login = "autologin" for password-autologin flow.
#
# --- PAM SERVICE SUMMARY ---
#
# login/sddm/polkit/hyprlock:
#   Password only — pam_gnome_keyring captures the SDDM password to unlock the keyring.
#
# sudo:
#   YubiKey only:      YubiKey → Password
#   TOTP only:         OTP (3 attempts) → Password
#   Both:              YubiKey → OTP (3 attempts) → Password
#
# polkit:
#   Password only — TOTP/YubiKey excluded to allow keyring auto-unlock.
#
# SSH:
#   TOTP only:         Public-Key + OTP
#   YubiKey only:      Public-Key + YubiKey
#   Both:              Public-Key + (YubiKey or OTP)
#   Password never allowed over SSH.
#
# --- SETUP SCRIPTS ---
#
#   totp-init         — Generate TOTP secret
#   yubikey-init      — Register YubiKey for PAM auth
#   yubikey-luks-init — Enroll YubiKey FIDO2 for LUKS unlock
#   tpm-luks-init     — Enroll TPM2 for LUKS auto-unlock
#
# Files (with impermanence: /persist/etc/*):
#   users.oath    — TOTP secrets (pam_oath usersfile)
#   u2f_mappings  — YubiKey credentials (pam_u2f authfile)
#
# See also: ssh.nix, impermanence.nix, tpm.nix, hosts/*/luks.nix

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.features.auth;
  prefix = config.features.impermanence.persistPrefix;

  # Auth files use persistPrefix to bypass impermanence bind-mounts.
  # pam_oath/pam_u2f update files via temp + rename(), which fails across
  # bind-mount boundaries. See impermanence-pitfalls in memory.
  oathFile = "${prefix}/etc/users.oath";
  u2fFile = "${prefix}/etc/u2f_mappings";

  # LUKS devices for yubikey-luks-init script (same pattern as tpm.nix)
  luksDevices = config.boot.initrd.luks.devices;
  deviceList = lib.concatStringsSep " " (map (d: d.device) (lib.attrValues luksDevices));

  # Terminal services: support 3 OTP retries before password fallback
  terminalServices = [
    "sudo"
  ];

  # SDDM/polkit-1/hyprlock: password only (pam_gnome_keyring needs the login password)

  #--- CLI Tools ---

  totp-init = pkgs.writeShellApplication {
    name = "totp-init";
    runtimeInputs = with pkgs; [
      coreutils
      oath-toolkit
      qrencode
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
      step()    { echo ""; info "[$1/$2] $3"; }

      echo ""
      echo -e "''${BOLD}TOTP Setup''${RESET}"
      echo -e "''${DIM}Configure time-based one-time password (2FA) for sudo and SSH''${RESET}"
      echo ""

      OATH_FILE="${oathFile}"
      USERNAME="''${SUDO_USER:-$USER}"
      HOSTNAME="$(hostname)"

      # Check for existing secret
      if [[ -f "$OATH_FILE" ]] && grep -q "HOTP/T30/6 $USERNAME " "$OATH_FILE" 2>/dev/null; then
        info "Current status: enrolled"
        echo ""
        echo "  [r] Re-enroll (generate new secret)"
        echo "  [q] Quit"
      else
        info "Current status: not enrolled"
        echo ""
        echo "  [e] Enroll (generate secret)"
        echo "  [q] Quit"
      fi
      echo ""
      read -rp "Choice: " CHOICE
      case "$CHOICE" in
        e|E|r|R) ;; # continue below
        *)
          echo "Aborted."
          exit 0
          ;;
      esac

      # Generate 20-byte random secret (hex)
      SECRET_HEX=$(od -An -tx1 -N20 /dev/urandom | tr -d ' \n')

      # Convert to base32 for QR code / authenticator app
      SECRET_B32=$(printf '%s' "$SECRET_HEX" | sed 's/../\\x&/g' | xargs -0 printf '%b' | base32 | tr -d '\n')

      # Write oath usersfile — create with restricted permissions atomically
      # Format: HOTP/T30/6 = TOTP with 30s period and 6 digits
      install -m 600 /dev/null "$OATH_FILE"
      echo "HOTP/T30/6 $USERNAME - $SECRET_HEX" > "$OATH_FILE"

      echo ""
      info "Scan this QR code with your authenticator app:"
      echo ""
      qrencode -t ANSIUTF8 "otpauth://totp/NixOS:''${USERNAME}@''${HOSTNAME}?secret=''${SECRET_B32}&issuer=NixOS"
      echo ""
      echo -e "  ''${BOLD}Backup secret (base32):''${RESET} $SECRET_B32"
      echo ""

      # Verify OTP before confirming
      VERIFIED=false
      for _ in 1 2 3; do
        read -rp "Enter OTP code to verify: " OTP_CODE
        EXPECTED=$(oathtool --totp -d 6 "$SECRET_HEX")
        if [[ "$OTP_CODE" == "$EXPECTED" ]]; then
          VERIFIED=true
          break
        fi
        warn "Incorrect. Try again."
      done

      if [[ "$VERIFIED" != "true" ]]; then
        rm -f "$OATH_FILE"
        error "Verification failed — secret not saved."
      fi

      echo ""
      success "TOTP configured for $USERNAME."
    '';
  };

  yubikey-luks-init = pkgs.writeShellApplication {
    name = "yubikey-luks-init";
    runtimeInputs = with pkgs; [
      systemd
      gawk
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
      step()    { echo ""; info "[$1/$2] $3"; }

      echo ""
      echo -e "''${BOLD}YubiKey LUKS Setup''${RESET}"
      echo -e "''${DIM}Enroll YubiKey FIDO2 for encrypted disk unlock at boot''${RESET}"
      echo ""

      DEVICES=(${deviceList})

      if [[ ''${#DEVICES[@]} -eq 0 ]]; then
        error "No LUKS devices found in NixOS config."
      fi

      # List FIDO2 slot numbers on a device
      get_fido2_slots() {
        systemd-cryptenroll "$1" 2>/dev/null | awk '$2=="fido2"{print $1}'
      }

      # Enroll the currently inserted YubiKey on all devices
      do_enroll() {
        echo ""
        info "Make sure your YubiKey is inserted before continuing."
        echo ""
        read -rsp "Enter LUKS password: " PASSWORD
        echo ""
        PASS_FILE="$(mktemp)"
        trap 'rm -f "$PASS_FILE"' EXIT
        printf '%s' "$PASSWORD" > "$PASS_FILE"
        chmod 600 "$PASS_FILE"

        ENROLL_OK=true
        for dev in "''${DEVICES[@]}"; do
          ATTEMPT=0
          DEV_OK=false
          while [[ $ATTEMPT -lt 3 ]]; do
            ATTEMPT=$(( ATTEMPT + 1 ))
            info "Touch your YubiKey to enroll on $(basename "$dev") (attempt $ATTEMPT/3)..."
            if systemd-cryptenroll "$dev" --fido2-device=auto --fido2-with-client-pin=no --unlock-key-file="$PASS_FILE"; then
              success "$(basename "$dev"): enrolled"
              DEV_OK=true
              break
            else
              warn "$(basename "$dev"): attempt $ATTEMPT failed"
            fi
          done
          if [[ "$DEV_OK" != "true" ]]; then
            ENROLL_OK=false
          fi
        done

        if [[ "$ENROLL_OK" != "true" ]]; then
          error "Enrollment failed. Check that your YubiKey is inserted and supports FIDO2."
        fi

        echo ""
        success "YubiKey enrolled on all devices. Touch the key at boot to unlock."
      }

      # Wipe a specific slot number (or "fido2" for all) from all devices
      do_wipe_slot() {
        local slot=$1
        for dev in "''${DEVICES[@]}"; do
          echo -e "    ''${DIM}$(basename "$dev"):''${RESET} wiping slot $slot..."
          systemd-cryptenroll "$dev" --wipe-slot="$slot" || true
        done
      }

      #--- Status ---

      info "LUKS devices (from NixOS config):"
      echo ""
      for dev in "''${DEVICES[@]}"; do
        mapfile -t SLOTS < <(get_fido2_slots "$dev")
        COUNT=''${#SLOTS[@]}
        if [[ $COUNT -gt 0 ]]; then
          STATUS="$COUNT FIDO2 key(s) enrolled (slots: ''${SLOTS[*]})"
        else
          STATUS="no FIDO2 keys enrolled"
        fi
        echo "  $(basename "$dev") ($dev) — $STATUS"
      done
      echo ""

      # Use first device as reference for slot numbers
      mapfile -t REF_SLOTS < <(get_fido2_slots "''${DEVICES[0]}")
      SLOT_COUNT=''${#REF_SLOTS[@]}

      #--- First enrollment or existing-key menu ---

      if [[ $SLOT_COUNT -eq 0 ]]; then
        info "No FIDO2 keys enrolled."
        echo ""
        echo "  [e] Enroll YubiKey"
        echo "  [q] Quit"
        echo ""
        read -rp "Choice: " CHOICE
        case "$CHOICE" in
          e|E) do_enroll ;;
          *)
            echo "Aborted."
            exit 0
            ;;
        esac
      else
        info "Current status: $SLOT_COUNT FIDO2 key(s) enrolled"
        echo ""
        echo "  [a] Add key"
        echo "  [d] Delete key"
        echo "  [q] Quit"
        echo ""
        read -rp "Choice: " CHOICE

        case "$CHOICE" in
          a|A)
            do_enroll
            ;;
          d|D)
            if [[ $SLOT_COUNT -eq 1 ]]; then
              read -rp "Delete the only enrolled key? [y/N] " CONFIRM
              if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
                echo "Aborted."
                exit 0
              fi
              do_wipe_slot fido2
              success "FIDO2 key removed."
            else
              echo ""
              for i in "''${!REF_SLOTS[@]}"; do
                echo "  [$((i+1))] slot ''${REF_SLOTS[$i]}"
              done
              echo ""
              read -rp "Delete which key? (1-$SLOT_COUNT, 'a' for all) " DEL_CHOICE

              if [[ "$DEL_CHOICE" == "a" || "$DEL_CHOICE" == "A" ]]; then
                do_wipe_slot fido2
                success "All FIDO2 keys removed."
              elif [[ "$DEL_CHOICE" =~ ^[0-9]+$ ]] && (( DEL_CHOICE >= 1 && DEL_CHOICE <= SLOT_COUNT )); then
                SLOT_TO_DEL="''${REF_SLOTS[$((DEL_CHOICE-1))]}"
                do_wipe_slot "$SLOT_TO_DEL"
                success "Key #$DEL_CHOICE (slot $SLOT_TO_DEL) removed. $((SLOT_COUNT-1)) key(s) remaining."
              else
                error "Invalid choice."
              fi
            fi
            ;;
          *)
            echo "Aborted."
            exit 0
            ;;
        esac
      fi
    '';
  };

  yubikey-init = pkgs.writeShellApplication {
    name = "yubikey-init";
    runtimeInputs = with pkgs; [ pam_u2f ];
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
      step()    { echo ""; info "[$1/$2] $3"; }

      echo ""
      echo -e "''${BOLD}YubiKey PAM Setup''${RESET}"
      echo -e "''${DIM}Register a YubiKey for sudo and SSH authentication''${RESET}"
      echo ""

      USERNAME="''${SUDO_USER:-$USER}"
      MAPPINGS_FILE="${u2fFile}"

      # Parse existing keys for this user
      # Format: username:KeyHandle1,Key1,CoseType1,Opts1:KeyHandle2,Key2,CoseType2,Opts2
      if [[ -f "$MAPPINGS_FILE" ]] && grep -q "^$USERNAME:" "$MAPPINGS_FILE" 2>/dev/null; then
        USER_LINE=$(grep "^$USERNAME:" "$MAPPINGS_FILE")
        # Split credentials (everything after "username:") by ":"
        CREDS_STR="''${USER_LINE#*:}"
        IFS=':' read -ra CREDS <<< "$CREDS_STR"
        KEY_COUNT=''${#CREDS[@]}

        info "Current status: $KEY_COUNT key(s) registered for $USERNAME"
        echo ""
        for i in "''${!CREDS[@]}"; do
          # Show truncated key handle as identifier
          HANDLE="''${CREDS[$i]%%,*}"
          echo "  [$((i+1))] ...''${HANDLE: -12}"
        done
        echo ""
        echo "  [a] Add another key"
        echo "  [d] Delete key(s)"
        echo "  [q] Quit"
        echo ""
        read -rp "Choice: " CHOICE

        case "$CHOICE" in
          a|A)
            echo ""
            info "Insert your NEW YubiKey and touch the button when it flashes"
            echo ""
            NEW_CRED=$(pamu2fcfg -n)
            if [[ -z "$NEW_CRED" ]]; then
              error "Failed to read YubiKey. Make sure it is inserted and try again."
            fi
            sed -i "s|^$USERNAME:.*|&:$NEW_CRED|" "$MAPPINGS_FILE"
            success "YubiKey registered for $USERNAME."
            ;;
          d|D)
            if [[ $KEY_COUNT -eq 1 ]]; then
              read -rp "Delete the only registered key? [y/N] " CONFIRM
              if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
                echo "Aborted."
                exit 0
              fi
              sed -i "/^$USERNAME:/d" "$MAPPINGS_FILE"
              success "All keys removed for $USERNAME."
            else
              echo ""
              echo "Delete which key? (1-$KEY_COUNT, 'a' for all)"
              read -rp "Choice: " DEL_CHOICE

              if [[ "$DEL_CHOICE" == "a" || "$DEL_CHOICE" == "A" ]]; then
                sed -i "/^$USERNAME:/d" "$MAPPINGS_FILE"
                success "All keys removed for $USERNAME."
              elif [[ "$DEL_CHOICE" =~ ^[0-9]+$ ]] && (( DEL_CHOICE >= 1 && DEL_CHOICE <= KEY_COUNT )); then
                # Remove the selected credential and rebuild the line
                unset "CREDS[$((DEL_CHOICE-1))]"
                REMAINING=""
                for cred in "''${CREDS[@]}"; do
                  if [[ -n "$REMAINING" ]]; then
                    REMAINING="$REMAINING:$cred"
                  else
                    REMAINING="$cred"
                  fi
                done
                sed -i "s|^$USERNAME:.*|$USERNAME:$REMAINING|" "$MAPPINGS_FILE"
                success "Key #$DEL_CHOICE removed. $((KEY_COUNT-1)) key(s) remaining."
              else
                error "Invalid choice."
              fi
            fi
            ;;
          *)
            echo "Aborted."
            exit 0
            ;;
        esac
      else
        info "Current status: no keys registered"
        echo ""
        info "Insert your YubiKey and touch the button when it flashes"
        echo ""
        CREDENTIALS=$(pamu2fcfg -u "$USERNAME")
        if [[ -z "$CREDENTIALS" ]]; then
          error "Failed to read YubiKey. Make sure it is inserted and try again."
        fi
        # Create with restricted permissions if not yet existing
        if [[ ! -f "$MAPPINGS_FILE" ]]; then
          install -m 600 /dev/null "$MAPPINGS_FILE"
        fi
        echo "$CREDENTIALS" >> "$MAPPINGS_FILE"
        success "YubiKey registered for $USERNAME."
      fi

      chmod 600 "$MAPPINGS_FILE"
    '';
  };
in
{
  options.features.auth = {
    totp.enable = (lib.mkEnableOption "TOTP two-factor authentication") // {
      default = true;
    };
    yubikey = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = config.features.encryption.unlockMethod == "yubikey";
        description = "Enable YubiKey authentication tools and PAM integration.";
      };
    };
  };

  config = lib.mkMerge [

    #--- Shared: SSH server settings when any 2FA is enabled ---
    (lib.mkIf (cfg.totp.enable || cfg.yubikey.enable) {
      services.openssh.settings = {
        PasswordAuthentication = false;
        AuthenticationMethods = "publickey,keyboard-interactive";
        KbdInteractiveAuthentication = true;
      };

      # SSH: No password, 2FA handles it
      security.pam.services.sshd.unixAuth = false;
    })

    #--- TOTP ---
    (lib.mkIf cfg.totp.enable {

      environment.systemPackages = [
        pkgs.oath-toolkit # pam_oath + oathtool CLI
        pkgs.qrencode # QR code generation for setup
        totp-init
      ];

      # Global oath settings (apply to all services with oathAuth = true)
      # usersFile points directly to /persist to avoid bind-mount rename() issue:
      security.pam.oath = {
        usersFile = oathFile;
        window = 3; # Allow 3 time steps (~1.5 min clock skew)
        # digits = 6 (default)
      };

      # sudo + SSH: 3 OTP attempts before fallback
      # [success=done default=ignore] = if correct → done, if wrong → try next
      # After 3 failures: sudo → password prompt (pam_unix), SSH → denied (pam_deny)
      # login/sddm excluded: TOTP prompts break SDDM's greeter.
      security.pam.services = lib.genAttrs [ "sudo" "sshd" ] (_: {
        oathAuth = true;
        rules.auth = {
          oath.control = lib.mkForce "[success=done default=ignore]";
          oath_retry2 = {
            order = 11120;
            control = "[success=done default=ignore]";
            modulePath = "${pkgs.oath-toolkit}/lib/security/pam_oath.so";
            args = [
              "usersfile=${oathFile}"
              "window=3"
              "digits=6"
            ];
          };
          oath_retry3 = {
            order = 11140;
            control = "[success=done default=ignore]";
            modulePath = "${pkgs.oath-toolkit}/lib/security/pam_oath.so";
            args = [
              "usersfile=${oathFile}"
              "window=3"
              "digits=6"
            ];
          };
        };
      })
      # login/sddm: oath excluded — SDDM's greeter mishandles multi-prompt PAM.
      # polkit-1/sddm: also excluded for keyring (see above).
      ;
    })

    #--- YubiKey ---
    (lib.mkIf cfg.yubikey.enable {

      environment.systemPackages = [
        pkgs.pam_u2f
        pkgs.yubikey-manager
        yubikey-init
      ];

      # Global u2f settings (uses FIDO2/CTAP2 when supported by the key)
      # control defaults to "sufficient" — correct for our use case
      security.pam.u2f.settings = {
        cue = true; # Show "Please touch the device" prompt
        authfile = u2fFile;
      };

      # sudo + SSH: YubiKey required
      # login/sddm/polkit/hyprlock: password only
      #   - pam_gnome_keyring needs the password at SDDM login to auto-unlock the keyring
      #   - LUKS unlock at boot covers the physical access protection
      security.pam.services =
        lib.genAttrs terminalServices (_: {
          u2fAuth = true;
        })
        // {
          sshd.u2fAuth = true;
        };
    })

    #--- YubiKey FIDO2 LUKS unlock ---
    (lib.mkIf (config.features.encryption.unlockMethod == "yubikey") {
      environment.systemPackages = [ yubikey-luks-init ];

      # FIDO2 in initrd requires systemd-based initrd
      # mkDefault: impermanence.nix can override if both are enabled
      boot.initrd.systemd.enable = lib.mkDefault true;

      # These libraries are dynamically loaded by systemd-cryptsetup for FIDO2.
      # Without them in the initrd store the YubiKey times out at boot despite
      # the USB device being visible.
      boot.initrd.systemd.storePaths = [
        pkgs.pcsclite.lib
        pkgs.libfido2
      ];

      # Add libfido2 as an initrd package so systemd-udevd picks up its
      # udev rules (70-u2f.rules) and identifies the YubiKey as FIDO2.
      boot.initrd.systemd.packages = [ pkgs.libfido2 ];

      # USB/FIDO2 enumeration can lag behind cryptsetup startup in initrd.
      # Poll only for Yubico hidraw devices; full udev settle is too slow on
      # desktops with many USB/HID devices and can wait for unrelated hardware.
      boot.initrd.systemd.services =
        {
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
                  props="$(udevadm info --query=property --name="$dev" 2>/dev/null || true)"
                  case "$props" in
                    *ID_VENDOR_ID=1050*) exit 0 ;;
                  esac
                done
                sleep 0.2
              done
            '';
          };

          # Late non-boot-critical USB/HID devices can keep initrd udev workers
          # busy after LUKS is already unlocked. Do not let that delay switch-root;
          # userspace udev coldplugs devices again after boot continues.
          "systemd-udevd" = {
            overrideStrategy = "asDropin";
            serviceConfig.TimeoutStopSec = "2s";
          };
        }
        // lib.mapAttrs' (name: _:
          lib.nameValuePair "systemd-cryptsetup@${name}" {
            overrideStrategy = "asDropin";
            after = [ "fido2-yubikey-wait.service" ];
            wants = [ "fido2-yubikey-wait.service" ];
          }
        ) config.boot.initrd.luks.devices;
    })

  ];
}
