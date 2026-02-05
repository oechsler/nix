{ config, lib, ... }:

{
  # Feature toggles consumed by multiple modules.
  # Single-module toggles (gaming, bluetooth, etc.) are defined in their own modules.
  options.features = {
    server = lib.mkEnableOption "server mode (disables desktop, audio, bluetooth, gaming, etc.)";
    desktop = {
      enable = (lib.mkEnableOption "desktop environment (Hyprland, SDDM, Firefox)") // { default = true; };
      wm = lib.mkOption {
        type = lib.types.enum [ "hyprland" "kde" ];
        default = "hyprland";
        description = "Window manager / desktop environment";
      };
    };
    development = {
      enable = (lib.mkEnableOption "development tools (IDEs, languages, K8s)") // { default = true; };
    };
    apps = {
      enable = (lib.mkEnableOption "desktop applications (Discord, Spotify, etc.)") // { default = true; };
    };
  };

  config = lib.mkIf config.features.server {
    features.desktop.enable = lib.mkDefault false;
    features.apps.enable = lib.mkDefault false;
    features.audio.enable = lib.mkDefault false;
    features.bluetooth.enable = lib.mkDefault false;
    features.gaming.enable = lib.mkDefault false;
    features.flatpak.enable = lib.mkDefault false;
    features.appimage.enable = lib.mkDefault false;
    features.wifi.enable = lib.mkDefault false;
  };
}
