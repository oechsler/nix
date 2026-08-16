# Common Desktop Modules (All WMs)
#
# This module imports desktop configuration shared across all window managers:
# - theme.nix - GTK/cursor theming
# - launchers.nix - Shared pinned applications
# - maintenance.nix - Home Manager activation housekeeping
# - xdg.nix - XDG user directories
# - bookmarks.nix - File manager sidebar bookmarks
# - autostart.nix - Autostart application list
# - idle.nix - Idle timeout options

{ lib, features, ... }:

{
  imports = [
    ./theme.nix
    ./launchers.nix
    ./maintenance.nix
    ./xdg.nix
    ./bookmarks.nix
    ./autostart.nix
    ./idle.nix
  ];

  home.sessionVariables.NIXOS_OZONE_WL = lib.mkIf features.desktop.enable "1";
}
