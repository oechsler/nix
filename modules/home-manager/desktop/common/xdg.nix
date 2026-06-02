# XDG Configuration
#
# This module configures XDG user directories and desktop entries.
#
# Features:
# - German directory names (Schreibtisch, Dokumente, Downloads, etc.)
# - Hide CUPS desktop entry (not needed in launcher)
# - Auto-create XDG directories

{ config, ... }:

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
        exec = "kitty nvim %F";
        icon = "nvim";
        terminal = false;
        categories = [ "Utility" "TextEditor" ];
        mimeType = [
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
      };
    };

    mimeApps = {
      enable = true;
      defaultApplications = {
        "application/pdf"            = [ "firefox.desktop" ];
        "text/plain"                 = [ "nvim.desktop" ];
        "text/markdown"              = [ "nvim.desktop" ];
        "text/x-script.python"       = [ "nvim.desktop" ];
        "text/x-shellscript"         = [ "nvim.desktop" ];
        "text/x-nix"                 = [ "nvim.desktop" ];
        "text/x-lua"                 = [ "nvim.desktop" ];
        "text/x-c"                   = [ "nvim.desktop" ];
        "text/x-c++"                 = [ "nvim.desktop" ];
        "text/x-go"                  = [ "nvim.desktop" ];
        "text/x-rust"                = [ "nvim.desktop" ];
        "text/x-java"                = [ "nvim.desktop" ];
        "text/x-javascript"          = [ "nvim.desktop" ];
        "text/x-typescript"          = [ "nvim.desktop" ];
        "text/css"                   = [ "nvim.desktop" ];
        "text/html"                  = [ "nvim.desktop" ];
        "text/xml"                   = [ "nvim.desktop" ];
        "application/json"           = [ "nvim.desktop" ];
        "application/x-yaml"         = [ "nvim.desktop" ];
        "application/toml"           = [ "nvim.desktop" ];
      };
    };

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
