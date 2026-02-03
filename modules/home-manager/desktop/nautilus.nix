{ config, pkgs, ... }:

{
  # GNOME Nautilus Dateimanager
  home.packages = with pkgs; [
    nautilus
    xdg-user-dirs-gtk  # Für korrekte Seitenleiste
  ];

  # XDG User Directories für Nautilus Seitenleiste
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
  };

  # xdg-user-dirs-gtk-update beim Login ausführen
  systemd.user.services.xdg-user-dirs-gtk = {
    Unit.Description = "Update XDG user dirs for GTK";
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.xdg-user-dirs-gtk}/bin/xdg-user-dirs-gtk-update";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
