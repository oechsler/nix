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
    ../../modules/system/fonts.nix
    ../../modules/system/theme.nix

    # Desktop
    ../../modules/desktop/sddm.nix
    ../../modules/desktop/hyprland.nix

    # Programs
    ../../modules/programs
  ];

  # sops-nix configuration
  sops = {
    defaultSopsFile = ../../sops/sops.encrypted.yaml;
    age.keyFile = "/home/samuel/.config/sops/age/keys.txt";
    # WiFi secrets werden automatisch in networking.nix generiert
  };

  # Flakes
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Host-spezifisch
  networking.hostName = "samuels-pc";
  
  # Home Manager
  home-manager = {
    extraSpecialArgs = {
      inherit inputs;
      fonts = config.fonts.defaults;
      theme = config.theme;
    };
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

  # GVFS für Nautilus (Disks, Trash, Netzwerk)
  services.gvfs.enable = true;
  services.udisks2.enable = true;

  # Theme-Werte können hier überschrieben werden:
  # theme.catppuccin.flavor = "frappe";
  # theme.catppuccin.accent = "blue";

  system.stateVersion = "25.11";
}
