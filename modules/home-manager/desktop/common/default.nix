# Common Desktop Modules (All WMs)
#
# This module imports desktop configuration shared across all window managers:
# - theme.nix - GTK/cursor theming, pinned apps
# - xdg.nix - XDG user directories
# - bookmarks.nix - File manager sidebar bookmarks
# - autostart.nix - Autostart application list
# - idle.nix - Idle timeout options

{ lib, features, ... }:

{
  imports = [
    ./theme.nix
    ./xdg.nix
    ./bookmarks.nix
    ./autostart.nix
    ./idle.nix
  ];

  home.sessionVariables.NIXOS_OZONE_WL = lib.mkIf features.desktop.enable "1";

  # Some Electron launchers read this directly instead of relying solely on the
  # nixpkgs NIXOS_OZONE_WL wrapper behavior.
  xdg.configFile."electron-flags.conf" = lib.mkIf features.desktop.enable {
    text = ''
      --ozone-platform=wayland
    '';
  };
}
