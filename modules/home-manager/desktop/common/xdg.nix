# XDG Configuration
#
# This module configures XDG user directories and desktop entries.
#
# Features:
# - German directory names (Schreibtisch, Dokumente, Downloads, etc.)
# - Hide CUPS desktop entry (not needed in launcher)
# - Auto-create XDG directories

{
  config,
  features,
  lib,
  ...
}:

let
  isKde = features.desktop.wm == "kde";
  browserEnabled = features.desktop.browser.enable;
  browser = features.desktop.browser.type;
  editorMimeTypes = [
    "text/plain"
    "text/markdown"
    "text/x-script.python"
    "text/x-shellscript"
    "text/x-nix"
    "text/x-lua"
    "text/x-c"
    "text/x-c++"
    "text/x-go"
    "text/x-rust"
    "text/x-java"
    "text/x-javascript"
    "text/x-typescript"
    "text/css"
    "text/html"
    "text/xml"
    "application/json"
    "application/x-yaml"
    "application/toml"
  ];
in

{
  xdg = {
    desktopEntries = {
      # Hide CUPS from application launchers
      cups = {
        name = "CUPS";
        noDisplay = true;
      };

      # Neovim wrapper for GUI file managers (opens in Kitty)
      nvim = {
        name = "Neovim";
        genericName = "Text Editor";
        exec = "kitty --class nvim nvim %F";
        icon = "nvim";
        terminal = false;
        settings.StartupWMClass = "nvim";
        categories = [
          "Utility"
          "TextEditor"
        ];
        mimeType = editorMimeTypes;
      };

    };

    mimeApps = {
      enable = true;
      defaultApplications = lib.optionalAttrs browserEnabled (
        lib.genAttrs editorMimeTypes (_: [ "nvim.desktop" ])
        // {
          "application/pdf" = [ "${browser}.desktop" ];
        }
      );
    };

    # KDE rewrites mimeapps.list through System Settings and file dialogs.
    # Keep declarative defaults authoritative for Plasma sessions.
    configFile."mimeapps.list".force = isKde;

    # German directory names are intentional — all hosts belong to the same German-speaking user.
    # To add a non-German host: override these in the host's home.nix.
    userDirs = {
      enable = true;
      createDirectories = true;
      setSessionVariables = false;
      desktop = "${config.home.homeDirectory}/Schreibtisch";
      documents = "${config.home.homeDirectory}/Dokumente";
      download = "${config.home.homeDirectory}/Downloads";
      music = "${config.home.homeDirectory}/Musik";
      pictures = "${config.home.homeDirectory}/Bilder";
      publicShare = "${config.home.homeDirectory}/Öffentlich";
      templates = "${config.home.homeDirectory}/Vorlagen";
      videos = "${config.home.homeDirectory}/Videos";
    };
  };
}
