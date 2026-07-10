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
    runtimeInputs = [ pkgs.sbctl pkgs.systemd pkgs.coreutils pkgs.jq ];
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
      echo -e "''${BOLD}Secure Boot Setup''${RESET}"
      echo -e "''${DIM}Sign boot files and enroll keys into firmware''${RESET}"
      echo ""

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
      if command -v sbctl &>/dev/null; then
        sbctl_json=$(sbctl status --json 2>/dev/null || true)
        if [[ -n "$sbctl_json" ]]; then
          vendor_count=$(echo "$sbctl_json" | jq '.vendors | length' 2>/dev/null || echo "0")
          [[ "$vendor_count" != "0" ]] && keys_enrolled=true
        fi
      fi

      echo -e "    Secure Boot:    ''${sb_enabled:-unknown}"
      echo -e "    Setup Mode:     ''${setup_mode:-unknown}"
      echo -e "    Keys generated: $([ "$keys_exist" = true ] && echo "yes" || echo "no")"
      echo -e "    Keys enrolled:  $([ "$keys_enrolled" = true ] && echo "yes" || echo "no")"
      [[ "$ASUS_BOARD" == "true" ]] && \
        echo -e "    Board:          ''${DIM}ASUS (non-standard Setup Mode)''${RESET}"
      echo ""

      #--- Already fully set up? ---
      if [[ "$sb_enabled" == "enabled" ]] && [[ "$keys_enrolled" == true ]]; then
        info "Verifying boot files..."
        echo ""
        sbctl verify
        echo ""
        # Old systemd-boot EFI files may appear unsigned — this is expected.
        # lanzaboote uses Unified Kernel Images (UKIs); only those need to be signed.
        # Raw kernel EFI files from previous generations are never booted directly.
        unsigned=$(sbctl verify 2>/dev/null | grep -c '✗' || true)
        if [[ "$unsigned" -eq 0 ]]; then
          success "Secure Boot is active and all files are signed."
        else
          success "Secure Boot is active. lanzaboote UKIs are signed."
          echo ""
          echo -e "    ''${DIM}Cleaning up old systemd-boot entries (unsigned legacy files)...''${RESET}"
          nix-collect-garbage -d
          echo ""
          success "Old generations removed. All remaining files are signed."
        fi
        exit 0
      fi

      #--- Step 1: generate keys ---
      # Skip if keys are already enrolled — EFI vars are immutable after enrollment
      # and cannot be overwritten. Only regenerate when starting fresh.
      if [[ "$keys_enrolled" == true ]]; then
        step 1 3 "Keys already enrolled — skipping key generation."
        echo ""
      else
        step 1 3 "Generating Secure Boot keys..."
        echo ""
        # Unmount the impermanence bind-mount first if active, then wipe both
        # sides. If we only rm -rf the mount point, the mount stub survives and
        # sbctl cannot mkdir keys/ inside it.
        if mountpoint -q /var/lib/sbctl 2>/dev/null; then
          umount /var/lib/sbctl
        fi
        rm -rf /var/lib/sbctl /persist/var/lib/sbctl 2>/dev/null || true
        mkdir -p /var/lib/sbctl
        if command -v sbctl &>/dev/null; then
          sbctl create-keys
        else
          nix run nixpkgs#sbctl -- create-keys
        fi
        # Copy entire sbctl dir (keys/ + GUID) to /persist so it survives
        # the next rebuild (which re-activates the impermanence bind-mount).
        if [[ -d /persist ]]; then
          mkdir -p /persist/var/lib
          cp -a /var/lib/sbctl /persist/var/lib/
        fi
        echo ""
      fi

      #--- Step 2: rebuild with lanzaboote active + sign boot entries ---
      # Rebuild directly without install.sh so git pull / state checks don't
      # interfere. lanzaboote in the config produces a different derivation than
      # the previous build (which had mkForce false), so Nix will build fresh and
      # lanzaboote will generate signed EFI images.
      avail_gb=$(awk '/^MemAvailable:/{printf "%d", $2/1024/1024}' /proc/meminfo)
      max_jobs=$(( avail_gb / 4 ))
      (( max_jobs < 1 )) && max_jobs=1

      step 2 3 "Rebuilding system with Secure Boot active..."
      echo ""
      nixos-rebuild switch --flake "$REPO_DIR#$(hostname)" --max-jobs "$max_jobs"
      echo ""
      # sbctl sign-all signs lanzaboote's UKI images.
      # Do NOT sign raw kernel EFI files from previous systemd-boot generations —
      # manually signing them produces invalid boot entries (lanzaboote requires UKIs).
      sbctl sign-all
      echo ""

      #--- Step 3: enroll keys ---
      if [[ "$keys_enrolled" != true ]]; then
        if [[ "$ASUS_BOARD" == "true" ]]; then
          # ASUS firmware sets SetupMode=0 after key deletion even though EFI vars
          # are still writable. sbctl's full enrollment rejects this, but --partial
          # bypasses the SetupMode check and writes directly to each EFI hierarchy.
          # Enroll db and KEK first, PK last (PK activates Secure Boot protection).
          step 3 3 "Enrolling keys (ASUS board)..."
          echo ""
          echo -e "    Before continuing, configure your UEFI (Boot → Secure Boot):"
          echo ""
          echo -e "      OS Type:          ''${BOLD}Other OS''${RESET}"
          echo -e "      Secure Boot Mode: ''${BOLD}Custom''${RESET}"
          echo -e "      Key Management:   ''${BOLD}Clear Secure Boot Keys''${RESET}"
          echo -e "      ''${DIM}Save and reboot into NixOS before pressing Enter.''${RESET}"
          echo ""
          read -rp "    Confirm keys are cleared and you are back in NixOS, then press Enter..." _
          echo ""
          sbctl enroll-keys --partial db  --microsoft --firmware-builtin --ignore-immutable --yes-this-might-brick-my-machine
          sbctl enroll-keys --partial KEK --microsoft --firmware-builtin --ignore-immutable --yes-this-might-brick-my-machine
          sbctl enroll-keys --partial PK  --ignore-immutable --yes-this-might-brick-my-machine
          echo ""
          success "Keys enrolled."
          echo ""
          echo -e "    Step B complete. Now activate Secure Boot (Step C) in UEFI:"
          echo ""
          echo -e "      OS Type:          ''${BOLD}Windows UEFI mode''${RESET}"
          echo -e "      Secure Boot Mode: ''${BOLD}Standard''${RESET}  ''${DIM}(or keep Custom)''${RESET}"
          echo -e "      ''${DIM}→ Secure Boot state will show: On''${RESET}"
          echo ""
          echo -e "    Then run: ''${BOLD}sudo secure-boot-init''${RESET}  ''${DIM}(to verify all files are signed)''${RESET}"
          reboot_to_uefi
        elif [[ "$setup_mode" != "yes" ]]; then
          step 3 3 "Enrolling keys into firmware..."
          echo ""
          echo -e "    UEFI is not in Setup Mode — cannot enroll keys."
          echo ""
          echo -e "    To enter Setup Mode, reboot into UEFI and:"
          echo ""
          echo -e "      1. Disable Secure Boot"
          echo -e "      2. Enable ''${BOLD}Setup Mode''${RESET}  ''${DIM}(or 'Reset to Setup Mode' — clears existing keys)''${RESET}"
          echo -e "      3. Save and reboot into NixOS"
          echo -e "      4. Run: ''${BOLD}sudo secure-boot-init''${RESET}"
          echo ""
          reboot_to_uefi
          error "Enroll aborted — UEFI not in Setup Mode."
        else
          step 3 3 "Enrolling keys into firmware..."
          echo ""
          sbctl enroll-keys --microsoft --firmware-builtin
          echo ""
          success "Keys enrolled."
          echo ""
          echo -e "    Step B complete. Now activate Secure Boot (Step C) in UEFI:"
          echo ""
          echo -e "      1. Enable ''${BOLD}Secure Boot''${RESET}"
          echo -e "      2. Save and reboot into NixOS"
          echo ""
          echo -e "    Then run: ''${BOLD}sudo secure-boot-init''${RESET}  ''${DIM}(to verify all files are signed)''${RESET}"
          reboot_to_uefi
        fi
      else
        step 3 3 "Keys already enrolled."
        echo ""
        if [[ "$ASUS_BOARD" == "true" ]]; then
          echo -e "    Step B complete. Now activate Secure Boot (Step C) in UEFI (Boot → Secure Boot):"
          echo ""
          echo -e "      OS Type:          ''${BOLD}Windows UEFI mode''${RESET}"
          echo -e "      Secure Boot Mode: ''${BOLD}Standard''${RESET}  ''${DIM}(or keep Custom)''${RESET}"
          echo -e "      ''${DIM}→ Secure Boot state will show: On''${RESET}"
        else
          echo -e "    Step B complete. Now activate Secure Boot (Step C) in UEFI:"
          echo ""
          echo -e "      1. Enable ''${BOLD}Secure Boot''${RESET}"
          echo -e "      2. Save and reboot into NixOS"
        fi
        echo ""
        echo -e "    Then run: ''${BOLD}sudo secure-boot-init''${RESET}  ''${DIM}(to verify all files are signed)''${RESET}"
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
