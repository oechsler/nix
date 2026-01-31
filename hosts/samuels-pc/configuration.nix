{ config, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    inputs.home-manager.nixosModules.default
    inputs.catppuccin.nixosModules.catppuccin

    # System modules
    ../../modules/system/boot.nix
    ../../modules/system/compat.nix
    ../../modules/system/networking.nix
    ../../modules/system/locale.nix
    ../../modules/system/users.nix
    ../../modules/system/audio.nix
    ../../modules/system/bluetooth.nix

    # Desktop
    ../../modules/desktop/plasma.nix
    ../../modules/desktop/hyprland.nix

    # Programs
    ../../modules/programs
  ];

  # sops-nix configuration
  sops = {
    defaultSopsFile = ../../sops/sops.encrypted.yaml;
    age.keyFile = "/home/samuel/.config/sops/age/keys.txt";
    secrets = {
      wifi_ssid = {};
      wifi_psk = {};
    };
  };

  # Flakes
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Host-spezifisch
  networking.hostName = "samuels-pc";
  
  # Home Manager
  home-manager = {
    extraSpecialArgs = { inherit inputs; };
    users.samuel = {
      imports = [
        ./home.nix
        inputs.catppuccin.homeModules.catppuccin
      ];
    };
    backupFileExtension = "bak";
  };
    
  # System
  nixpkgs.config.allowUnfree = true;
  services.printing.enable = true;

  # Catppuccin system-wide theming
  catppuccin = {
    enable = true;
    flavor = "mocha";
    accent = "lavender";
  };

  system.stateVersion = "25.11";
}
