# Dolphin Configuration (KDE File Manager)
#
# This module configures Dolphin's sidebar bookmarks (Places panel).
#
# Features:
# - Declarative sidebar bookmarks from fileManager.bookmarks
# - Automatic hiding of unwanted XDG directories
# - Always shows: Home, configured bookmarks, Trash
# - Hides XDG directories not in fileManager.bookmarks
#
# How it works:
# 1. Generate user-places.xbel (KDE's bookmark format)
# 2. Add home directory and configured bookmarks
# 3. Mark unwanted XDG directories as hidden
# 4. Add trash at the bottom
#
# XDG directories checked:
# - Desktop, Documents, Downloads, Music, Pictures, Public, Templates, Videos
# - Only shown if explicitly added to fileManager.bookmarks

{ config, lib, ... }:

let
  home = config.home.homeDirectory;
  bookmarks = config.fileManager.bookmarks;
  bookmarkedPaths = map (b: b.path) bookmarks;

  # XDG directories that Dolphin auto-discovers
  # We hide any that aren't explicitly bookmarked
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

  # XDG directories not in fileManager.bookmarks (to be hidden)
  hiddenPlaces = builtins.filter (d: !(builtins.elem d.path bookmarkedPaths)) xdgPlaces;

  # Generate visible bookmark entry (XBEL format)
  entry = b: ''
    <bookmark href="file://${b.path}">
     <title>${b.name}</title>
     <info><metadata owner="http://freedesktop.org">
      <bookmark:icon name="${b.icon}"/>
     </metadata></info>
    </bookmark>'';

  # Generate hidden bookmark entry (XBEL format with IsHidden flag)
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
  #===========================
  # Configuration
  #===========================

  # Generate Dolphin sidebar bookmarks (user-places.xbel)
  # Format: XBEL (XML Bookmark Exchange Language)
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
