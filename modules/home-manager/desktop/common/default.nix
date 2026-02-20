# Common Desktop Modules (All WMs)
#
# This module imports desktop configuration shared across all window managers:
# - theme.nix - GTK/cursor theming, pinned apps
# - xdg.nix - XDG user directories
# - bookmarks.nix - File manager sidebar bookmarks
# - autostart.nix - Autostart application list
# - idle.nix - Idle timeout options

{
  imports = [
    ./theme.nix
    ./xdg.nix
    ./bookmarks.nix
    ./autostart.nix
    ./idle.nix
  ];
}
