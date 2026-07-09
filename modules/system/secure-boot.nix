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

      FLAKE="$(eval echo ~"''${SUDO_USER:-$USER}")/repos/nix#$(hostname)"

      echo ""
      echo "==> Secure Boot Setup"
      echo ""

      #--- Read current state ---
      bootctl_out=$(bootctl status 2>/dev/null || true)
      sb_enabled=$(echo "$bootctl_out" | awk '/Secure Boot:/{print $3}')
      setup_mode=$(echo "$bootctl_out" | awk '/Setup Mode:/{print $3}')
      lanza_active=$(echo "$bootctl_out" | grep -c "lanzaboote" || true)
      keys_exist=false
      [[ -f /var/lib/sbctl/keys/db/db.pem ]] && keys_exist=true
      keys_enrolled=false
      if sbctl status 2>/dev/null | grep -q "Secure Boot:.*true\|Enrolled keys:.*true\|enrolled"; then
        keys_enrolled=true
      fi

      echo "    Secure Boot:    ''${sb_enabled:-unknown}"
      echo "    Setup Mode:     ''${setup_mode:-unknown}"
      echo "    Keys generated: $([ "$keys_exist" = true ] && echo "yes" || echo "no")"
      echo "    Keys enrolled:  $([ "$keys_enrolled" = true ] && echo "yes" || echo "no")"
      echo ""

      #--- Already fully set up? ---
      if [[ "$sb_enabled" == "enabled" ]] && [[ "$keys_enrolled" == true ]]; then
        echo "==> Verifying all boot files are signed..."
        echo ""
        sbctl verify
        echo ""
        echo "    Secure Boot is active and all files are signed."
        exit 0
      fi

      #--- Step 1: generate keys first (lanzaboote needs them before rebuild) ---
      if [[ "$keys_exist" != true ]]; then
        echo "==> Step 1/4: Generating Secure Boot keys..."
        echo ""
        sbctl create-keys
        echo ""
      else
        echo "    Step 1/4: Keys already present."
        echo ""
      fi

      #--- Step 2: activate lanzaboote + sign boot entries ---
      echo "==> Step 2/4: Activating lanzaboote and signing boot entries..."
      echo ""
      nixos-rebuild switch --flake "$FLAKE"
      echo ""

      #--- Step 3: enroll keys (requires Setup Mode) ---
      if [[ "$keys_enrolled" != true ]]; then
        if [[ "$setup_mode" != "yes" && "$setup_mode" != "true" && "$setup_mode" != "1" ]]; then
          echo "!! Step 3/3: UEFI is not in Setup Mode — cannot enroll keys."
          echo ""
          echo "   To continue:"
          echo "   1. Reboot into UEFI/BIOS firmware setup"
          echo "   2. Disable Secure Boot"
          echo "   3. Enable Setup Mode (clears existing keys)"
          echo "   4. Reboot into NixOS"
          echo "   5. Run: sudo secure-boot-init"
          exit 1
        fi
        echo "==> Step 3/3: Enrolling keys into firmware..."
        echo ""
        sbctl enroll-keys --microsoft
        echo ""
        echo "    Keys enrolled. Reboot and enable Secure Boot in UEFI/BIOS."
        echo "    Then run: sudo secure-boot-init (to verify)"
      else
        echo "    Step 3/3: Keys already enrolled."
        echo ""
        echo "    Enable Secure Boot in UEFI/BIOS if not already done."
        echo "    Then run: sudo secure-boot-init (to verify)"
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

  config = lib.mkIf cfg.enable {
    # Lanzaboote replaces systemd-boot
    boot.loader.systemd-boot.enable = lib.mkForce false;

    boot.lanzaboote = {
      enable = true;
      pkiBundle = "/var/lib/sbctl";
    };

    environment.systemPackages = [
      pkgs.sbctl
      secure-boot-init
    ];
  };
}
