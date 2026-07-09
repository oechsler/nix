# Secure Boot with lanzaboote
#
# Setup (run after first boot):
#   sudo secure-boot-init
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.features.secureBoot;

  secure-boot-init = pkgs.writeShellApplication {
    name = "secure-boot-init";
    runtimeInputs = [ pkgs.sbctl pkgs.systemd pkgs.coreutils ];
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
      echo -e "''${BOLD}Secure Boot Setup''${RESET}"
      echo -e "''${DIM}Sign boot files and enroll keys into firmware''${RESET}"
      echo ""

      FLAKE="$(eval echo ~"''${SUDO_USER:-''${USER}}")/repos/nix#$(hostname)"

      # Guard: refuse to run if Secure Boot is not enabled in the flake config.
      # Read at runtime from the flake so the install-time override (mkForce false)
      # does not permanently disable this script on the installed system.
      REPO_DIR="$(eval echo ~"''${SUDO_USER:-''${USER}}")/repos/nix"

      sb_in_config=false
      grep -q 'secureBoot\.enable\s*=\s*true' "$REPO_DIR/hosts/$(hostname)/configuration.nix" 2>/dev/null \
        && sb_in_config=true
      if [[ "$sb_in_config" != "true" ]]; then
        warn "features.secureBoot.enable is not set for this host."
        warn ""
        warn "To fix:"
        warn "  1. Edit $REPO_DIR/hosts/$(hostname)/configuration.nix"
        warn "     and set: features.secureBoot.enable = true;"
        warn "  2. Re-run the installer to apply the change:"
        warn "     sudo $REPO_DIR/install.sh"
        warn "  3. Then run this script again: sudo secure-boot-init"
        echo ""
        exit 1
      fi


      reboot_to_uefi() {
        echo ""
        read -rp "    Reboot into UEFI firmware setup now? [Y/n]: " confirm
        if [[ ! "$confirm" =~ ^[nN]$ ]]; then
          systemctl reboot --firmware-setup
        fi
      }

      #--- Detect ASUS boards (non-compliant Setup Mode behaviour) ---
      # ASUS firmware clears keys → Secure Boot disabled instead of entering Setup Mode.
      # Workaround: set OS Type = Other OS + Secure Boot Mode = Custom in UEFI,
      # which allows sbctl to enroll keys without requiring explicit Setup Mode.
      board_vendor="$(cat /sys/class/dmi/id/board_vendor 2>/dev/null || true)"
      sys_vendor="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
      ASUS_BOARD=false
      if [[ "$board_vendor" == *"ASUSTeK"* || "$board_vendor" == *"ASUS"* || \
            "$sys_vendor" == *"ASUSTeK"* || "$sys_vendor" == *"ASUS"* ]]; then
        ASUS_BOARD=true
      fi

      #--- Read current state ---
      bootctl_out=$(bootctl status 2>/dev/null || true)
      sb_enabled=$(echo "$bootctl_out" | awk '/Secure Boot:/{print $3}')
      setup_mode=$(echo "$bootctl_out" | awk '/Setup Mode:/{print $3}')
      keys_exist=false
      [[ -f /var/lib/sbctl/keys/db/db.pem && -f /var/lib/sbctl/keys/db/db.key ]] && keys_exist=true
      keys_enrolled=false
      if sbctl status 2>/dev/null | grep -q "Secure Boot:.*true\|Enrolled keys:.*true\|enrolled"; then
        keys_enrolled=true
      fi

      echo -e "  ''${BOLD}Secure Boot:''${RESET}    ''${sb_enabled:-unknown}"
      echo -e "  ''${BOLD}Setup Mode:''${RESET}     ''${setup_mode:-unknown}"
      echo -e "  ''${BOLD}Keys generated:''${RESET} $([ "$keys_exist" = true ] && echo "yes" || echo "no")"
      echo -e "  ''${BOLD}Keys enrolled:''${RESET}  $([ "$keys_enrolled" = true ] && echo "yes" || echo "no")"
      if [[ "$ASUS_BOARD" == "true" ]]; then
        echo -e "  ''${BOLD}Board vendor:''${RESET}   ASUS (non-standard Setup Mode — Custom Mode required)"
      fi
      echo ""

      #--- Already fully set up? ---
      if [[ "$sb_enabled" == "enabled" ]] && [[ "$keys_enrolled" == true ]]; then
        info "Verifying all boot files are signed..."
        echo ""
        sbctl verify
        echo ""
        success "Secure Boot is active and all files are signed."
        exit 0
      fi

      #--- Step 1: generate keys ---
      if [[ "$keys_exist" != true ]]; then
        step 1 3 "Generating Secure Boot keys..."
        echo ""
        sbctl create-keys
        echo ""
      else
        step 1 3 "Keys already present — skipping key generation."
        echo ""
      fi

      #--- Step 2: activate lanzaboote + sign boot entries ---
      # Keys must exist before this rebuild so impermanence persists /var/lib/sbctl.
      # After this step the keys survive reboots — safe to reboot for BIOS changes.
      step 2 3 "Rebuilding system with Secure Boot active (persists keys across reboots)..."
      echo ""
      "$REPO_DIR/install.sh" --yes --quiet
      echo ""

      #--- Step 3: enroll keys ---
      if [[ "$keys_enrolled" != true ]]; then
        if [[ "$ASUS_BOARD" == "true" ]]; then
          # ASUS firmware sets SetupMode=0 after key deletion even though EFI vars
          # are still writable. sbctl's full enrollment rejects this, but --partial
          # bypasses the SetupMode check and writes directly to each EFI hierarchy.
          # Enroll db and KEK first, PK last (PK activates Secure Boot protection).
          step 3 3 "Enrolling keys (ASUS board — partial enrollment to bypass SetupMode check)..."
          echo ""
          warn "Before continuing, configure your UEFI (Boot → Secure Boot):"
          warn "  1. OS Type:           Other OS"
          warn "  2. Secure Boot Mode:  Custom"
          warn "  3. Key Management:    Clear Secure Boot Keys"
          warn "  4. Save and reboot into NixOS"
          echo ""
          read -rp "Confirm keys are cleared and you are back in NixOS, then press Enter..." _
          echo ""
          sbctl enroll-keys --partial db --microsoft --firmware-builtin
          sbctl enroll-keys --partial KEK --microsoft --firmware-builtin
          sbctl enroll-keys --partial PK
          echo ""
          success "Keys enrolled."
          info "Now reboot into UEFI and activate Secure Boot:"
          info "  OS Type:           Windows UEFI mode"
          info "  Secure Boot Mode:  Standard  (or keep Custom)"
          info "  → Secure Boot state will show: On"
          info ""
          info "Then run: sudo secure-boot-init  (to verify signatures)"
          reboot_to_uefi
        elif [[ "$setup_mode" != "yes" ]]; then
          step 3 3 "Enrolling keys into firmware..."
          echo ""
          warn "UEFI is not in Setup Mode — cannot enroll keys."
          warn "To continue:"
          warn "  1. Reboot into UEFI/BIOS firmware setup"
          warn "  2. Disable Secure Boot"
          warn "  3. Enable Setup Mode (clears existing keys)"
          warn "  4. Reboot into NixOS"
          warn "  5. Run: sudo secure-boot-init"
          echo ""
          reboot_to_uefi
          error "Enroll aborted — UEFI not in Setup Mode."
        else
          step 3 3 "Enrolling keys into firmware..."
          echo ""
          sbctl enroll-keys --microsoft --firmware-builtin
          echo ""
          success "Keys enrolled."
          info "Reboot into UEFI and enable Secure Boot."
          info "Then run: sudo secure-boot-init (to verify)"
          reboot_to_uefi
        fi
      else
        step 3 3 "Keys already enrolled."
        echo ""
        info "Enable Secure Boot in UEFI/BIOS if not already done."
        info "Then run: sudo secure-boot-init (to verify)"
        reboot_to_uefi
      fi
      echo ""
    '';
  };
in
{
  imports = [
    inputs.lanzaboote.nixosModules.lanzaboote
  ];

  options.features.secureBoot = {
    enable = lib.mkEnableOption "Secure Boot via lanzaboote";
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      # Lanzaboote replaces systemd-boot
      boot.loader.systemd-boot.enable = lib.mkForce false;

      boot.lanzaboote = {
        enable = true;
        pkiBundle = "/var/lib/sbctl";
      };
    })

    # Always install sbctl and secure-boot-init so the script is available
    # even when Secure Boot is temporarily disabled (e.g. during initial install).
    {
      environment.systemPackages = [
        pkgs.sbctl
        secure-boot-init
      ];
    }
  ];
}
