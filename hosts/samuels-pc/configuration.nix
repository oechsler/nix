{ config, pkgs, inputs, ... }:

{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix
    inputs.home-manager.nixosModules.default
    inputs.catppuccin.nixosModules.catppuccin

    ../../modules
  ];

  networking.hostName = "samuels-pc";

  # ─── Host-specific overrides ─────────────────────────────────────────────────

  # Second NVMe SSD for games (not managed by disko - do not format)
  fileSystems."/mnt/games" = {
    device = "/dev/nvme1n1p1";
    fsType = "btrfs";
    options = [ "compress=zstd" "noatime" ];
  };
  systemd.tmpfiles.rules = [
    "d /mnt/games 0755 samuel users -"
  ];

  displays.monitors = [
    { name = "DP-1"; width = 2560; height = 1440; refreshRate = 165; x = 0; y = 0; }
    { name = "DP-2"; width = 2560; height = 1440; refreshRate = 165; x = 2560; y = 0; }
  ];

  # Home Manager
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
