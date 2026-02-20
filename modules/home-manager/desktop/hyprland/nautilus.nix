# Nautilus Configuration (GNOME Files)
#
# This module configures Nautilus as the file manager for Hyprland.
#
# Features:
# - Declarative GTK bookmarks from fileManager.bookmarks
# - Prevents Nextcloud from adding bookmarks (force = true)
# - Auto-update XDG user directories (German names)
#
# Packages:
# - nautilus - File manager
# - file-roller - Archive manager (for extracting archives in Nautilus)
# - xdg-user-dirs-gtk - Updates ~/.config/user-dirs.dirs

{ config, pkgs, lib, ... }:

{
  #===========================
  # Configuration
  #===========================

  # Packages
  home.packages = with pkgs; [
    nautilus
    file-roller
    xdg-user-dirs-gtk
  ];

  # Prevent Nextcloud from adding bookmarks
  xdg.configFile."gtk-3.0/bookmarks".force = true;
  xdg.configFile."gtk-3.0/bookmarks".text = let
    entry = b: "file://${b.path} ${b.name}";
  in lib.concatMapStringsSep "\n" entry config.fileManager.bookmarks + "\n";

  systemd.user.services.xdg-user-dirs-gtk = {
    Unit.Description = "Update XDG user dirs for GTK";
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.xdg-user-dirs-gtk}/bin/xdg-user-dirs-gtk-update";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
