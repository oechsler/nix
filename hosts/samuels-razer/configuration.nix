{ config, pkgs, inputs, ... }:

{
  imports = [
    # ./disko.nix  # Uncomment when reinstalling with BTRFS
    ./hardware-configuration.nix
    inputs.home-manager.nixosModules.default
    inputs.catppuccin.nixosModules.catppuccin

    # System modules
    ../../modules/system/nix.nix
    ../../modules/system/sops.nix
    ../../modules/system/boot.nix
    # ../../modules/system/secure-boot.nix  # Uncomment for Secure Boot (Windows dual-boot)
    ../../modules/system/compat.nix
    ../../modules/system/networking.nix
    ../../modules/system/locale.nix
    ../../modules/system/users.nix
    ../../modules/system/audio.nix
    ../../modules/system/bluetooth.nix
    ../../modules/system/fonts.nix
    ../../modules/system/theme.nix
    ../../modules/system/hardware.nix
    ../../modules/system/virtualisation.nix
    ../../modules/system/power.nix
    ../../modules/system/smb.nix
    ../../modules/system/gaming.nix

    # Desktop
    ../../modules/desktop/sddm.nix
    ../../modules/desktop/hyprland.nix

    # Programs
    ../../modules/programs
  ];

  networking.hostName = "samuels-razer";

  # ─── Host-specific overrides ─────────────────────────────────────────────────
  theme.scale = 1.6;
  theme.wallpaper = ../../backgrounds/nix-black-4k.png;

  # Home Manager - passes config to home-manager modules
  home-manager = {
    extraSpecialArgs = {
      inherit inputs;
      fonts = config.fonts.defaults;
      theme = config.theme;
      locale = config.locale;
      user = config.user;
    };
    users.${config.user.name} = {
      imports = [
        ./home.nix
        inputs.catppuccin.homeModules.catppuccin
        inputs.sops-nix.homeManagerModules.sops
      ];
    };
    backupFileExtension = "bak";
  };

  system.stateVersion = "25.11";
}
