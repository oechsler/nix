# Secure Boot with lanzaboote
#
# Setup (run after first boot):
#   secure-boot-init (elevates via sudo when needed)
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
    runtimeInputs = [
      pkgs.sbctl
      pkgs.systemd
      pkgs.uutils-coreutils-noprefix
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
      echo -e "''${BOLD}Secure Boot Setup''${RESET}"
      echo -e "''${DIM}Sign boot files and enroll keys into firmware''${RESET}"
      echo ""

      # Guard: refuse to run if Secure Boot is not enabled in the flake config.
      # Read at runtime from the flake so the install-time override (mkForce false)
      # does not permanently disable this script on the installed system.
       REPO_DIR=${lib.escapeShellArg "${config.users.users.${config.user.name}.home}/repos/nix"}
       HOST_CONFIG="$REPO_DIR/hosts/${config.networking.hostName}/configuration.nix"
       IMPERMANENCE_ENABLED=${lib.boolToString config.features.impermanence.enable}

       sb_in_config=false
       if [[ -f "$HOST_CONFIG" ]] && ${pkgs.gnugrep}/bin/grep -Eq \
         '^[[:space:]]*secureBoot\.enable[[:space:]]*=[[:space:]]*true[[:space:]]*;' "$HOST_CONFIG"; then
         sb_in_config=true
       fi
       if [[ "$sb_in_config" != "true" ]]; then
         warn "features.secureBoot.enable is not set for this host."
         warn "Checked: $HOST_CONFIG"
         warn ""
         warn "To fix:"
         warn "  1. Edit $HOST_CONFIG"
        warn "     and set: features.secureBoot.enable = true;"
        warn "  2. Re-run the installer to apply the change:"
        warn "     sudo $REPO_DIR/install.sh"
        warn "  3. Then run this script again: secure-boot-init"
        echo ""
        exit 1
      fi

      reboot_to_uefi() {
        echo ""
        read -rp "    Reboot into UEFI firmware setup now? [Y/n]: " confirm
        if [[ ! "$confirm" =~ ^[nN]$ ]]; then
         ${pkgs.systemd}/bin/systemctl reboot --firmware-setup
        fi
      }

      #--- Detect ASUS boards (non-compliant Setup Mode behaviour) ---
      # ASUS firmware clears keys → Secure Boot disabled instead of entering Setup Mode.
      # Workaround: set OS Type = Other OS + Secure Boot Mode = Custom in UEFI,
      # which allows sbctl to enroll keys without requiring explicit Setup Mode.
       board_vendor="$(${pkgs.coreutils}/bin/cat /sys/class/dmi/id/board_vendor 2>/dev/null || true)"
       sys_vendor="$(${pkgs.coreutils}/bin/cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
      ASUS_BOARD=false
      if [[ "$board_vendor" == *"ASUSTeK"* || "$board_vendor" == *"ASUS"* || \
            "$sys_vendor" == *"ASUSTeK"* || "$sys_vendor" == *"ASUS"* ]]; then
        ASUS_BOARD=true
      fi

      #--- Read current state ---
       bootctl_out=$(${pkgs.systemd}/bin/bootctl status 2>/dev/null || true)
       sb_enabled=$(printf '%s\n' "$bootctl_out" | ${pkgs.gnused}/bin/sed -nE 's/^[[:space:]]*Secure Boot:[[:space:]]*([^[:space:]]+).*/\L\1/p' | ${pkgs.coreutils}/bin/head -n1)
       setup_mode_raw=$(printf '%s\n' "$bootctl_out" | ${pkgs.gnused}/bin/sed -nE 's/^[[:space:]]*Setup Mode:[[:space:]]*([^[:space:]]+).*/\L\1/p' | ${pkgs.coreutils}/bin/head -n1)
       setup_mode=unknown
       case "$setup_mode_raw" in
         yes|true|enabled|enable|setup|on) setup_mode=yes ;;
         no|false|disabled|disable|off) setup_mode=no ;;
       esac
       if [[ "$setup_mode" == unknown ]]; then
         sbctl_status=$(${pkgs.sbctl}/bin/sbctl --debug status 2>/dev/null || true)
         if printf '%s\n' "$sbctl_status" | ${pkgs.gnugrep}/bin/grep -Eiq \
           'Setup Mode:.*(yes|true|enabled|enable|setup|on)'; then
           setup_mode=yes
         elif printf '%s\n' "$sbctl_status" | ${pkgs.gnugrep}/bin/grep -Eiq \
           'Setup Mode:.*(no|false|disabled|disable|off)'; then
           setup_mode=no
         fi
       fi
       keys_exist=false
       [[ -f /var/lib/sbctl/keys/db/db.pem && -f /var/lib/sbctl/keys/db/db.key ]] && keys_exist=true
       if [[ "$keys_exist" != true && "$IMPERMANENCE_ENABLED" == true ]] \
         && [[ -f /persist/var/lib/sbctl/keys/db/db.pem && -f /persist/var/lib/sbctl/keys/db/db.key ]] \
         && ! ${pkgs.util-linux}/bin/mountpoint -q /var/lib/sbctl 2>/dev/null; then
         ${pkgs.coreutils}/bin/mkdir -p /var/lib
         ${pkgs.coreutils}/bin/cp -a /persist/var/lib/sbctl /var/lib/
         keys_exist=true
       fi
       keys_enrolled=false
       sbctl_status=$(${pkgs.sbctl}/bin/sbctl --debug status 2>/dev/null || true)
       enrolled_keys=$(${pkgs.sbctl}/bin/sbctl list-enrolled-keys 2>/dev/null || true)
       if printf '%s\n' "$sbctl_status" | ${pkgs.gnugrep}/bin/grep -q 'db is fine' \
         || printf '%s\n' "$enrolled_keys" | ${pkgs.gnugrep}/bin/grep -Eq '^[[:space:]]+Database Key[[:space:]]*$'; then
         keys_enrolled=true
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
         ${pkgs.sbctl}/bin/sbctl verify
        echo ""
        success "Secure Boot is active. lanzaboote UKIs are signed."
        warn "Unsigned entries above are old systemd-boot EFI files — expected, never booted directly."
        exit 0
      fi

       #--- Step 1: generate keys ---
       step 1 3 "Generating Secure Boot keys..."
       echo ""
       # Firmware enrollment may still be pending, but replacing the matching
       # private keys would make the existing certificates unusable.
       if [[ "$keys_exist" == true ]]; then
         success "Secure Boot keys already exist. Reusing existing keys."
       else
        # Unmount the impermanence bind-mount first if active, then wipe both
        # sides. If we only rm -rf the mount point, the mount stub survives and
        # sbctl cannot mkdir keys/ inside it.
         if [[ "$IMPERMANENCE_ENABLED" == true ]] && ${pkgs.util-linux}/bin/mountpoint -q /var/lib/sbctl 2>/dev/null; then
            ${pkgs.util-linux}/bin/umount /var/lib/sbctl
         fi
         ${pkgs.coreutils}/bin/rm -rf /var/lib/sbctl 2>/dev/null || true
         if [[ "$IMPERMANENCE_ENABLED" == true ]]; then
           ${pkgs.coreutils}/bin/rm -rf /persist/var/lib/sbctl 2>/dev/null || true
         fi
         ${pkgs.coreutils}/bin/mkdir -p /var/lib/sbctl
         if [ -x ${pkgs.sbctl}/bin/sbctl ]; then
            ${pkgs.sbctl}/bin/sbctl create-keys 2>&1 | ${pkgs.gnused}/bin/sed 's/^/    /'
         else
            ${pkgs.nix}/bin/nix run nixpkgs#sbctl -- create-keys 2>&1 | ${pkgs.gnused}/bin/sed 's/^/    /'
         fi
         if [[ ! -f /var/lib/sbctl/keys/db/db.pem || ! -f /var/lib/sbctl/keys/db/db.key ]]; then
           error "sbctl did not create the expected db.pem/db.key files under /var/lib/sbctl."
         fi
         keys_exist=true
         # Copy entire sbctl dir (keys/ + GUID) to /persist so it survives
        # the next rebuild (which re-activates the impermanence bind-mount).
         if [[ "$IMPERMANENCE_ENABLED" == true ]]; then
            ${pkgs.coreutils}/bin/mkdir -p /persist/var/lib
            ${pkgs.coreutils}/bin/cp -a /var/lib/sbctl /persist/var/lib/
            if [[ ! -f /persist/var/lib/sbctl/keys/db/db.pem ]]; then
              error "Secure Boot keys were not persisted to /persist/var/lib/sbctl."
            fi
        fi
         success "Secure Boot keys generated."
       fi
       echo ""

      #--- Step 2: rebuild with lanzaboote active + sign boot entries ---
      # Rebuild directly without install.sh so git pull / state checks don't
      # interfere. lanzaboote in the config produces a different derivation than
      # the previous build (which had mkForce false), so Nix will build fresh and
      # lanzaboote will generate signed EFI images.
       avail_gb=$(${pkgs.gawk}/bin/awk '/^MemAvailable:/{printf "%d", $2/1024/1024}' /proc/meminfo)
      max_jobs=$(( avail_gb / 4 ))
      (( max_jobs < 1 )) && max_jobs=1

      step 2 3 "Rebuilding system with Secure Boot active..."
      echo ""
        ${pkgs.nixos-rebuild}/bin/nixos-rebuild switch --flake "$REPO_DIR#${config.networking.hostName}" --max-jobs "$max_jobs"
      echo ""
      # sbctl sign-all signs lanzaboote's UKI images.
      # Do NOT sign raw kernel EFI files from previous systemd-boot generations —
      # manually signing them produces invalid boot entries (lanzaboote requires UKIs).
       ${pkgs.sbctl}/bin/sbctl sign-all
      echo ""

       #--- Step 3: enroll keys ---
       step 3 3 "Enrolling Secure Boot keys..."
       echo ""
       if [[ "$keys_enrolled" == true ]]; then
         success "Secure Boot keys are already enrolled."
       elif [[ "$ASUS_BOARD" == true ]]; then
         # Some ASUS firmware reports SetupMode=0 while its EFI variables remain
         # writable. Enroll db and KEK first, then PK to activate Secure Boot.
         warn "Using ASUS firmware compatibility mode (partial enrollment)."
         echo "    Ensure the firmware is configured as follows before continuing:"
         echo "      OS Type:          Other OS"
         echo "      Secure Boot Mode: Custom"
         echo "      Key Management:   Clear Secure Boot Keys"
         echo ""
         read -rp "    Confirm the keys are cleared and press Enter..." _
         ${pkgs.sbctl}/bin/sbctl enroll-keys --partial db --microsoft --firmware-builtin \
           --ignore-immutable --yes-this-might-brick-my-machine
         ${pkgs.sbctl}/bin/sbctl enroll-keys --partial KEK --microsoft --firmware-builtin \
           --ignore-immutable --yes-this-might-brick-my-machine
         ${pkgs.sbctl}/bin/sbctl enroll-keys --partial PK --ignore-immutable \
           --yes-this-might-brick-my-machine
         success "Secure Boot keys enrolled using ASUS compatibility mode."
       elif [[ "$setup_mode" == yes ]]; then
         ${pkgs.sbctl}/bin/sbctl enroll-keys --microsoft --firmware-builtin
         success "Secure Boot keys enrolled."
       else
         error "UEFI is not in Setup Mode. Clear the existing keys in UEFI, reboot, and run secure-boot-init again."
       fi

       echo ""
       if [[ "$sb_enabled" != "enabled" ]]; then
         echo "    Activate Secure Boot in UEFI, then boot back into NixOS."
         if [[ "$ASUS_BOARD" == true ]]; then
           echo "    ASUS: use Windows UEFI mode and Standard Secure Boot mode."
         fi
         echo "    Run secure-boot-init again to verify the result."
         reboot_to_uefi
       else
         success "Secure Boot is active. Run secure-boot-init again to verify signed boot files."
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
