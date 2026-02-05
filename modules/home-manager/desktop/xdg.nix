{ config, ... }:

{
  xdg.desktopEntries.cups = {
    name = "CUPS";
    noDisplay = true;
  };

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
}
