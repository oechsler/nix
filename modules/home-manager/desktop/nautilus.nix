{ config, pkgs, lib, ... }:

{
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
