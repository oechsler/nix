{ lib, ... }:

{
  # Feature toggles consumed by multiple modules.
  # Single-module toggles (gaming, bluetooth, etc.) are defined in their own modules.
  options.features = {
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
}
