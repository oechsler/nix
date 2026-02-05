{ config, lib, ... }:

let
  home = config.home.homeDirectory;
in
{
  options.fileManager.bookmarks = lib.mkOption {
    type = lib.types.listOf (lib.types.submodule {
      options = {
        name = lib.mkOption { type = lib.types.str; description = "Display name"; };
        path = lib.mkOption { type = lib.types.str; description = "Absolute path"; };
        icon = lib.mkOption { type = lib.types.str; default = "folder"; description = "Icon name"; };
      };
    });
    default = [];
    description = "File manager sidebar bookmarks (used by Nautilus and Dolphin)";
  };

  config.fileManager.bookmarks = let
    dirs = config.xdg.userDirs;
    name = builtins.baseNameOf;
  in [
    { name = name dirs.download;  path = dirs.download;  icon = "folder-download"; }
    { name = name dirs.desktop;   path = dirs.desktop;   icon = "folder-desktop"; }
    { name = "Repos";             path = "${home}/repos"; icon = "folder-git"; }
    { name = name dirs.documents; path = dirs.documents;  icon = "folder-documents"; }
    { name = name dirs.pictures;  path = dirs.pictures;   icon = "folder-pictures"; }
  ];
}
