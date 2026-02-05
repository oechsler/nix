{ config, lib, ... }:

let
  home = config.home.homeDirectory;
  bookmarks = config.fileManager.bookmarks;
  bookmarkedPaths = map (b: b.path) bookmarks;

  # XDG directories that Dolphin auto-adds to the sidebar.
  # Any not present in fileManager.bookmarks are hidden automatically.
  dirs = config.xdg.userDirs;
  xdgPlaces = [
    { path = dirs.desktop;     icon = "folder-desktop"; }
    { path = dirs.documents;   icon = "folder-documents"; }
    { path = dirs.download;    icon = "folder-download"; }
    { path = dirs.music;       icon = "folder-music"; }
    { path = dirs.pictures;    icon = "folder-pictures"; }
    { path = dirs.publicShare; icon = "folder-public"; }
    { path = dirs.templates;   icon = "folder-templates"; }
    { path = dirs.videos;      icon = "folder-videos"; }
  ];

  hiddenPlaces = builtins.filter (d: !(builtins.elem d.path bookmarkedPaths)) xdgPlaces;

  entry = b: ''
    <bookmark href="file://${b.path}">
     <title>${b.name}</title>
     <info><metadata owner="http://freedesktop.org">
      <bookmark:icon name="${b.icon}"/>
     </metadata></info>
    </bookmark>'';

  hiddenEntry = d: ''
    <bookmark href="file://${d.path}">
     <title>${builtins.baseNameOf d.path}</title>
     <info><metadata owner="http://freedesktop.org">
      <bookmark:icon name="${d.icon}"/>
     </metadata>
     <metadata owner="http://www.kde.org">
      <IsHidden>true</IsHidden>
     </metadata></info>
    </bookmark>'';
in
{
  # Sidebar bookmarks (generated from fileManager.bookmarks)
  xdg.dataFile."user-places.xbel".force = true;
  xdg.dataFile."user-places.xbel".text = ''
    <?xml version="1.0" encoding="UTF-8"?>
    <xbel xmlns:bookmark="http://www.freedesktop.org/standards/desktop-bookmarks"
          xmlns:kdeconnect="http://www.kde.org"
          xmlns:mime="http://www.freedesktop.org/standards/shared-mime-info">
     <bookmark href="file://${home}">
      <title>Startseite</title>
      <info><metadata owner="http://freedesktop.org">
       <bookmark:icon name="user-home"/>
      </metadata></info>
     </bookmark>
    ${lib.concatMapStrings entry bookmarks}${lib.concatMapStrings hiddenEntry hiddenPlaces}
     <bookmark href="trash:/">
      <title>Papierkorb</title>
      <info><metadata owner="http://freedesktop.org">
       <bookmark:icon name="user-trash"/>
      </metadata></info>
     </bookmark>
    </xbel>
  '';
}
