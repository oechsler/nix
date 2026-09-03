# YubiKey PAM configuration and enrollment command.

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.features.auth.yubikey;
  u2fFile = "${config.features.impermanence.persistPrefix}/etc/u2f_mappings";
  yubikey-init = pkgs.writeShellApplication {
    name = "yubikey-init";
    runtimeInputs = with pkgs; [
      pam_u2f
      gnugrep
      gnused
      uutils-coreutils-noprefix
      sudo
    ];
    text = ''
      if [[ $EUID -ne 0 ]]; then exec sudo "$0" "$@"; fi
      RED='\033[0;31m' GREEN='\033[0;32m'
      BLUE='\033[0;34m' BOLD='\033[1m' RESET='\033[0m'
      info() { echo -e "''${BLUE}==>''${RESET} ''${BOLD}$*''${RESET}"; }
      success() { echo -e "    ''${GREEN}✓''${RESET} $*"; }
      error() { echo -e "''${RED}Error:''${RESET} $*" >&2; exit 1; }
      USERNAME="''${SUDO_USER:-$USER}"; MAPPINGS_FILE="${u2fFile}"
      if [[ -f "$MAPPINGS_FILE" ]] && grep -q "^$USERNAME:" "$MAPPINGS_FILE" 2>/dev/null; then
        USER_LINE=$(grep "^$USERNAME:" "$MAPPINGS_FILE")
        CREDS_STR="''${USER_LINE#*:}"; IFS=':' read -ra CREDS <<< "$CREDS_STR"; KEY_COUNT=''${#CREDS[@]}
        info "Current status: $KEY_COUNT key(s) registered for $USERNAME"; echo ""
        for i in "''${!CREDS[@]}"; do HANDLE="''${CREDS[$i]%%,*}"; echo "  [$((i+1))] ...''${HANDLE: -12}"; done
        echo ""; echo "  [a] Add another key"; echo "  [d] Delete key(s)"; echo "  [q] Quit"; echo ""
        read -rp "Choice: " CHOICE
        case "$CHOICE" in
          a|A) echo ""; info "Insert your NEW YubiKey and touch the button when it flashes"; echo ""; NEW_CRED=$(pamu2fcfg -n)
            [[ -n "$NEW_CRED" ]] || error "Failed to read YubiKey. Make sure it is inserted and try again."
            sed -i "s|^$USERNAME:.*|&:$NEW_CRED|" "$MAPPINGS_FILE"; success "YubiKey registered for $USERNAME." ;;
          d|D)
            if [[ $KEY_COUNT -eq 1 ]]; then
              read -rp "Delete the only registered key? [y/N] " CONFIRM
              [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]] || { echo "Aborted."; exit 0; }
              sed -i "/^$USERNAME:/d" "$MAPPINGS_FILE"
            else
              echo ""; echo "Delete which key? (1-$KEY_COUNT, 'a' for all)"; read -rp "Choice: " DEL_CHOICE
            fi
            if [[ $KEY_COUNT -eq 1 ]]; then :
            elif [[ "$DEL_CHOICE" == "a" || "$DEL_CHOICE" == "A" ]]; then sed -i "/^$USERNAME:/d" "$MAPPINGS_FILE"
            elif [[ "$DEL_CHOICE" =~ ^[0-9]+$ ]] && (( DEL_CHOICE >= 1 && DEL_CHOICE <= KEY_COUNT )); then
              unset "CREDS[$((DEL_CHOICE-1))]"; REMAINING=""
              for cred in "''${CREDS[@]}"; do if [[ -n "$REMAINING" ]]; then REMAINING="$REMAINING:$cred"; else REMAINING="$cred"; fi; done
              sed -i "s|^$USERNAME:.*|$USERNAME:$REMAINING|" "$MAPPINGS_FILE"
            else error "Invalid choice."; fi ;;
          *) echo "Aborted."; exit 0 ;;
        esac
      else
        info "Current status: no keys registered"; echo ""; info "Insert your YubiKey and touch the button when it flashes"; echo ""
        CREDENTIALS=$(pamu2fcfg -u "$USERNAME")
        [[ -n "$CREDENTIALS" ]] || error "Failed to read YubiKey. Make sure it is inserted and try again."
        [[ -f "$MAPPINGS_FILE" ]] || install -m 600 /dev/null "$MAPPINGS_FILE"
        echo "$CREDENTIALS" >> "$MAPPINGS_FILE"; success "YubiKey registered for $USERNAME."
      fi
      chmod 600 "$MAPPINGS_FILE"
    '';
  };
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.pam_u2f
      pkgs.yubikey-manager
      yubikey-init
    ];
    security.pam.u2f.settings = {
      cue = true;
      authfile = u2fFile;
    };
    security.pam.services = {
      sudo.u2fAuth = true;
      sshd.u2fAuth = true;
    };
  };
}
