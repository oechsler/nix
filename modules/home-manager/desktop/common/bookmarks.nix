# File Manager Bookmarks Configuration
#
# This module defines file manager sidebar bookmarks.
# Used by both Nautilus (GTK) and Dolphin (KDE).
#
# Default bookmarks:
# - Downloads
# - Desktop (Schreibtisch)
# - Repos (~/repos)
# - Documents (Dokumente)
# - Pictures (Bilder)
# - Nextcloud
#
# Configuration:
#   features.fileManager.bookmarks = [
#     { name = "My Folder"; path = "/path/to/folder"; icon = "folder"; }
#   ];

{
  config,
  features,
  lib,
  ...
}:

let
  home = config.home.homeDirectory;
  pathToUri =
    path: "file://${lib.replaceStrings [ "%" " " "#" "?" ] [ "%25" "%20" "%23" "%3F" ] path}";
in
{
  #===========================
  # Options
  #===========================

  options.fileManager.bookmarks = lib.mkOption {
    internal = true;
    type = lib.types.listOf (
      lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Display name";
          };
          path = lib.mkOption {
            type = lib.types.str;
            description = "Absolute path";
          };
          icon = lib.mkOption {
            type = lib.types.str;
            default = "folder";
            description = "Icon name";
          };
        };
      }
    );
    default = [ ];
    description = "Internal rendered file manager bookmarks.";
  };

  #===========================
  # Configuration
  #===========================

  config = {
    fileManager.bookmarks =
      let
        dirs = config.xdg.userDirs;
        name = builtins.baseNameOf;
        defaults =
          lib.optionals features.apps.nextcloud.enable [
            {
              name = "Nextcloud";
              path = "${home}/Nextcloud";
              icon = "folder-cloud";
            }
          ]
          ++ [
            {
              name = name dirs.download;
              path = dirs.download;
              icon = "folder-download";
            }
            {
              name = name dirs.desktop;
              path = dirs.desktop;
              icon = "folder-desktop";
            }
            {
              name = "Repos";
              path = "${home}/repos";
              icon = "folder-git";
            }
            {
              name = name dirs.documents;
              path = dirs.documents;
              icon = "folder-documents";
            }
            {
              name = name dirs.pictures;
              path = dirs.pictures;
              icon = "folder-pictures";
            }
          ];
      in
      lib.defaultTo defaults features.fileManager.bookmarks;

    # GTK file portals and Nautilus use this shared bookmark format.
    xdg.configFile."gtk-3.0/bookmarks" = {
      force = true;
      text =
        lib.concatMapStringsSep "\n" (
          bookmark: "${pathToUri bookmark.path} ${bookmark.name}"
        ) config.fileManager.bookmarks
        + "\n";
    };
  };
}
