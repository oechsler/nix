# TOTP PAM configuration and enrollment command.

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.features.auth.totp;
  oathFile = "${config.features.impermanence.persistPrefix}/etc/users.oath";
  totp-init = pkgs.writeShellApplication {
    name = "totp-init";
    runtimeInputs = with pkgs; [
      uutils-coreutils-noprefix
      oath-toolkit
      qrencode
    ];
    text = ''
      if [[ $EUID -ne 0 ]]; then exec sudo "$0" "$@"; fi
      RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m'
      BLUE='\033[0;34m' BOLD='\033[1m' DIM='\033[2m' RESET='\033[0m'
      info() { echo -e "''${BLUE}==>''${RESET} ''${BOLD}$*''${RESET}"; }
      success() { echo -e "    ''${GREEN}✓''${RESET} $*"; }
      warn() { echo -e "    ''${YELLOW}!''${RESET} $*"; }
      error() { echo -e "''${RED}Error:''${RESET} $*" >&2; exit 1; }
      echo ""; echo -e "''${BOLD}TOTP Setup''${RESET}"
      echo -e "''${DIM}Configure time-based one-time password (2FA) for sudo and SSH''${RESET}"; echo ""
      OATH_FILE="${oathFile}"; USERNAME="''${SUDO_USER:-$USER}"; HOSTNAME="$(hostname)"
      if [[ -f "$OATH_FILE" ]] && grep -q "HOTP/T30/6 $USERNAME " "$OATH_FILE" 2>/dev/null; then
        info "Current status: enrolled"; echo ""; echo "  [r] Re-enroll (generate new secret)"; echo "  [q] Quit"
      else
        info "Current status: not enrolled"; echo ""; echo "  [e] Enroll (generate secret)"; echo "  [q] Quit"
      fi
      echo ""; read -rp "Choice: " CHOICE
      case "$CHOICE" in e|E|r|R) ;; *) echo "Aborted."; exit 0 ;; esac
      SECRET_HEX=$(od -An -tx1 -N20 /dev/urandom | tr -d ' \n')
      SECRET_B32=$(printf '%s' "$SECRET_HEX" | sed 's/../\\x&/g' | xargs -0 printf '%b' | base32 | tr -d '\n')
      install -m 600 /dev/null "$OATH_FILE"
      echo "HOTP/T30/6 $USERNAME - $SECRET_HEX" > "$OATH_FILE"
      echo ""; info "Scan this QR code with your authenticator app:"; echo ""
      qrencode -t ANSIUTF8 "otpauth://totp/NixOS:''${USERNAME}@''${HOSTNAME}?secret=''${SECRET_B32}&issuer=NixOS"
      echo ""; echo -e "  ''${BOLD}Backup secret (base32):''${RESET} $SECRET_B32"; echo ""
      VERIFIED=false
      for _ in 1 2 3; do
        read -rp "Enter OTP code to verify: " OTP_CODE
        EXPECTED=$(oathtool --totp -d 6 "$SECRET_HEX")
        if [[ "$OTP_CODE" == "$EXPECTED" ]]; then VERIFIED=true; break; fi
        warn "Incorrect. Try again."
      done
      if [[ "$VERIFIED" != "true" ]]; then rm -f "$OATH_FILE"; error "Verification failed — secret not saved."; fi
      echo ""; success "TOTP configured for $USERNAME."
    '';
  };
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.oath-toolkit
      pkgs.qrencode
      totp-init
    ];
    security.pam.oath = {
      usersFile = oathFile;
      window = 3;
    };
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
    });
  };
}
