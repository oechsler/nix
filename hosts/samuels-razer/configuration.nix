{ config, pkgs, inputs, ... }:

{
  imports = [
    # ./disko.nix  # Uncomment when reinstalling with BTRFS
    ./hardware-configuration.nix
    inputs.home-manager.nixosModules.default
    inputs.catppuccin.nixosModules.catppuccin

    ../../modules
  ];

  networking.hostName = "samuels-razer";

  # ─── Host-specific overrides ─────────────────────────────────────────────────
  theme.wallpaper = ../../backgrounds/nix-black-4k.png;

  displays.monitors = [
    { name = "eDP-1"; width = 3200; height = 1800; refreshRate = 60; scale = 1.6; }
  ];

  features.desktop.wm = "kde";

  fonts.defaults.terminalSize = 9;

  # Home Manager - passes config to home-manager modules
  home-manager = {
    extraSpecialArgs = {
      inherit inputs;
      fonts = config.fonts.defaults;
      theme = config.theme;
      locale = config.locale;
      user = config.user;
      features = config.features;
      displays = config.displays;
      input = config.input;
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
