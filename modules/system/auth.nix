# 2FA Authentication (TOTP + YubiKey)
#
# Configuration:
#   features.auth.totp.enable = true;     # TOTP two-factor authentication (default: true)
#   features.auth.yubikey.enable = false;  # YubiKey authentication (FIDO2, touch only)
#   features.auth.yubikey.pin = false;    # Require FIDO2 PIN in addition to touch
#
# Auth flow (login/sddm/sudo):
#   TOTP only:            OTP (3 attempts) → Password
#   YubiKey only:         YubiKey → Password
#   Both:                 YubiKey → OTP (3 attempts) → Password
#   Note: sddm uses PAM "substack login", inherits login's config.
#
# Auth flow (polkit):
#   TOTP only:            Password only (oath excluded — multi-round conversation unreliable)
#   YubiKey only:         YubiKey touch or Password
#   Both:                 YubiKey touch or Password
#   polkit-agent-helper-1 sends each PAM prompt individually to the agent and reads
#   responses from stdin. oath needs a conversation round that most agents mishandle
#   (race conditions with socket activation, EOF on second prompt). u2f works because
#   it only needs PAM_TEXT_INFO (no response) + physical touch, no text input.
#
# Auth flow (SSH):
#   TOTP only:            Public-Key + OTP
#   YubiKey only:         Public-Key + YubiKey
#   Both:                 Public-Key + (YubiKey or OTP)
#   Password is never allowed over SSH.
#
# Setup:
#   totp-init    — Generate TOTP secret
#   yubikey-init — Register YubiKey
#
# Files (with impermanence: /persist/etc/*, without: /etc/*):
#   users.oath    — TOTP secrets (pam_oath usersfile)
#   u2f_mappings  — YubiKey credentials (pam_u2f authfile)
#
# See also: ssh.nix (SSH server), impermanence.nix

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

  # Terminal services: support 3 OTP retries before password fallback
  terminalServices = [
    "login"
    "sudo"
  ];

  # SDDM: single OTP attempt (graphical, but needs 2FA for login)
  # polkit-1: password only for oath (conversation protocol unreliable), u2f via touch

  #--- CLI Tools ---

  totp-init = pkgs.writeShellApplication {
    name = "totp-init";
    runtimeInputs = with pkgs; [
      coreutils
      python3
      oath-toolkit
      qrencode
    ];
    text = ''
      if [[ $EUID -ne 0 ]]; then
        exec sudo "$0" "$@"
      fi

      OATH_FILE="${oathFile}"
      USERNAME="''${SUDO_USER:-$USER}"
      HOSTNAME="$(hostname)"

      # Check for existing secret
      if [[ -f "$OATH_FILE" ]] && grep -q "HOTP/T30/6 $USERNAME " "$OATH_FILE" 2>/dev/null; then
        echo "TOTP secret exists for $USERNAME."
        echo ""
        echo "  [r] Re-enroll (generate new secret)"
        echo "  [q] Quit"
      else
        echo "No TOTP secret for $USERNAME."
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
      SECRET_B32=$(python3 -c "import base64; print(base64.b32encode(bytes.fromhex('$SECRET_HEX')).decode())")

      # Write oath usersfile
      # Format: HOTP/T30/6 = TOTP with 30s period and 6 digits
      echo "HOTP/T30/6 $USERNAME - $SECRET_HEX" > "$OATH_FILE"
      chmod 600 "$OATH_FILE"

      echo ""
      echo "Scan this QR code with your authenticator app:"
      echo ""
      qrencode -t ANSIUTF8 "otpauth://totp/''${USERNAME}@''${HOSTNAME}?secret=''${SECRET_B32}&issuer=NixOS"
      echo ""
      echo "Backup secret (base32): $SECRET_B32"
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
        echo "Incorrect. Try again."
      done

      if [[ "$VERIFIED" != "true" ]]; then
        echo "Verification failed. Removing secret."
        rm -f "$OATH_FILE"
        exit 1
      fi

      echo ""
      echo "TOTP configured for $USERNAME."
      echo "Run 'sudo nixos-rebuild switch' to activate PAM changes."
    '';
  };

  yubikey-init = pkgs.writeShellApplication {
    name = "yubikey-init";
    runtimeInputs = with pkgs; [ pam_u2f ];
    text = ''
      if [[ $EUID -ne 0 ]]; then
        exec sudo "$0" "$@"
      fi

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

        echo "Found $KEY_COUNT registered YubiKey(s) for $USERNAME:"
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
            echo "Insert your NEW YubiKey and press the button when prompted..."
            echo ""
            NEW_CRED=$(pamu2fcfg -n)
            if [[ -z "$NEW_CRED" ]]; then
              echo "Error: Failed to register YubiKey"
              exit 1
            fi
            sed -i "s|^$USERNAME:.*|&:$NEW_CRED|" "$MAPPINGS_FILE"
            echo "Additional YubiKey registered for $USERNAME."
            ;;
          d|D)
            if [[ $KEY_COUNT -eq 1 ]]; then
              read -rp "Delete the only registered key? [y/N] " CONFIRM
              if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
                echo "Aborted."
                exit 0
              fi
              sed -i "/^$USERNAME:/d" "$MAPPINGS_FILE"
              echo "All keys removed for $USERNAME."
            else
              echo ""
              echo "Delete which key? (1-$KEY_COUNT, 'a' for all)"
              read -rp "Choice: " DEL_CHOICE

              if [[ "$DEL_CHOICE" == "a" || "$DEL_CHOICE" == "A" ]]; then
                sed -i "/^$USERNAME:/d" "$MAPPINGS_FILE"
                echo "All keys removed for $USERNAME."
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
                echo "Key #$DEL_CHOICE removed. $((KEY_COUNT-1)) key(s) remaining."
              else
                echo "Invalid choice. Aborted."
                exit 1
              fi
            fi
            ;;
          *)
            echo "Aborted."
            exit 0
            ;;
        esac
      else
        echo "Insert your YubiKey and press the button when prompted..."
        echo ""
        CREDENTIALS=$(pamu2fcfg -u "$USERNAME")
        if [[ -z "$CREDENTIALS" ]]; then
          echo "Error: Failed to register YubiKey"
          exit 1
        fi
        echo "$CREDENTIALS" >> "$MAPPINGS_FILE"
        echo "YubiKey registered for $USERNAME."
      fi

      chmod 600 "$MAPPINGS_FILE"
      echo "Run 'sudo nixos-rebuild switch' to activate."
    '';
  };
in
{
  options.features.auth = {
    totp.enable = (lib.mkEnableOption "TOTP two-factor authentication") // {
      default = true;
    };
    yubikey.enable = lib.mkEnableOption "YubiKey authentication";
    yubikey.pin = lib.mkEnableOption "require FIDO2 PIN on YubiKey (in addition to touch)";
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

      # Terminal services + SSH: 3 OTP attempts before fallback
      # [success=done default=ignore] = if correct → done, if wrong → try next
      # After 3 failures: terminal → password prompt (pam_unix), SSH → denied (pam_deny)
      security.pam.services = lib.genAttrs (terminalServices ++ [ "sshd" ]) (_: {
        oathAuth = true;
        rules.auth = {
          oath.control = lib.mkForce "[success=done default=ignore]";
          oath_retry2 = {
            order = 11120;
            control = "[success=done default=ignore]";
            modulePath = "${pkgs.oath-toolkit}/lib/security/pam_oath.so";
            args = [ "usersfile=${oathFile}" "window=3" "digits=6" ];
          };
          oath_retry3 = {
            order = 11140;
            control = "[success=done default=ignore]";
            modulePath = "${pkgs.oath-toolkit}/lib/security/pam_oath.so";
            args = [ "usersfile=${oathFile}" "window=3" "digits=6" ];
          };
        };
      })
      # Note: sddm uses "substack login" so it inherits login's 3 OTP retries.
      # polkit-1: oath excluded — polkit-agent-helper-1 uses multi-round conversation
      # (PAM_PROMPT_ECHO_OFF per module), but agents handle this unreliably.
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
      }
      // lib.optionalAttrs cfg.yubikey.pin {
        userVerification = true; # Require FIDO2 PIN (touch alone is not enough)
      };

      # All local services + SSH: YubiKey as sufficient (single touch, no retry needed)
      # u2f control is already "sufficient" from global security.pam.u2f.control
      # polkit: u2f works — touch only, no text input needed from the agent
      security.pam.services =
        lib.genAttrs (terminalServices ++ [ "sddm" "polkit-1" ]) (_: {
          u2fAuth = true;
        })
        // {
          sshd.u2fAuth = true;
        };
    })

  ];
}
