{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    nautilus
    file-roller
    xdg-user-dirs-gtk
  ];

  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    desktop = "${config.home.homeDirectory}/Schreibtisch";
    documents = "${config.home.homeDirectory}/Dokumente";
    download = "${config.home.homeDirectory}/Downloads";
    music = "${config.home.homeDirectory}/Musik";
    pictures = "${config.home.homeDirectory}/Bilder";
    publicShare = "${config.home.homeDirectory}/Öffentlich";
    templates = "${config.home.homeDirectory}/Vorlagen";
    videos = "${config.home.homeDirectory}/Videos";
  };

  # Prevent Nextcloud from adding bookmarks
  xdg.configFile."gtk-3.0/bookmarks".force = true;
  xdg.configFile."gtk-3.0/bookmarks".text = let
    home = config.home.homeDirectory;
  in ''
    file://${home}/Downloads
    file://${home}/Schreibtisch
    file://${home}/repos Repos
    file://${home}/Bilder
  '';

  systemd.user.services.xdg-user-dirs-gtk = {
    Unit.Description = "Update XDG user dirs for GTK";
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.xdg-user-dirs-gtk}/bin/xdg-user-dirs-gtk-update";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
