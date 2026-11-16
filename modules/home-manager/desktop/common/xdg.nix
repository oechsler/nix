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
  pkgs,
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
  officeMimeApplications = lib.optionalAttrs features.apps.enable {
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document" = [
      "writer.desktop"
    ];
    "application/vnd.openxmlformats-officedocument.wordprocessingml.template" = [ "writer.desktop" ];
    "application/vnd.ms-word" = [ "writer.desktop" ];
    "application/msword" = [ "writer.desktop" ];
    "application/vnd.ms-word.document.macroEnabled.12" = [ "writer.desktop" ];
    "application/vnd.ms-word.template.macroEnabled.12" = [ "writer.desktop" ];
    "application/vnd.oasis.opendocument.text" = [ "writer.desktop" ];
    "application/vnd.oasis.opendocument.text-template" = [ "writer.desktop" ];
    "application/rtf" = [ "writer.desktop" ];
    "text/rtf" = [ "writer.desktop" ];

    "application/vnd.ms-powerpoint" = [ "impress.desktop" ];
    "application/vnd.ms-powerpoint.presentation.macroEnabled.12" = [ "impress.desktop" ];
    "application/vnd.ms-powerpoint.template.macroEnabled.12" = [ "impress.desktop" ];
    "application/vnd.oasis.opendocument.presentation" = [ "impress.desktop" ];
    "application/vnd.openxmlformats-officedocument.presentationml.presentation" = [
      "impress.desktop"
    ];
    "application/vnd.openxmlformats-officedocument.presentationml.template" = [
      "impress.desktop"
    ];
    "application/vnd.openxmlformats-officedocument.presentationml.slideshow" = [
      "impress.desktop"
    ];

    "application/vnd.ms-excel" = [ "calc.desktop" ];
    "application/vnd.ms-excel.template.macroEnabled.12" = [ "calc.desktop" ];
    "application/vnd.oasis.opendocument.spreadsheet" = [ "calc.desktop" ];
    "application/vnd.oasis.opendocument.spreadsheet-template" = [ "calc.desktop" ];
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" = [
      "calc.desktop"
    ];
    "application/vnd.openxmlformats-officedocument.spreadsheetml.template" = [ "calc.desktop" ];
    "application/vnd.ms-excel.sheet.macroEnabled.12" = [ "calc.desktop" ];
    "application/vnd.ms-excel.sheet.binary.macroEnabled.12" = [ "calc.desktop" ];
    "text/csv" = [ "calc.desktop" ];
    "text/tab-separated-values" = [ "calc.desktop" ];
  };
  photocraftMimeTypes = [
    "application/x-photocraft"
    "image/x-paintnet"
    "image/openraster"
    "application/x-krita"
    "image/vnd.adobe.photoshop"
    "image/x-psd"
    "image/x-psb"
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
        exec = "${pkgs.kitty}/bin/kitty --class nvim ${pkgs.neovim}/bin/nvim %F";
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
      defaultApplications =
        lib.optionalAttrs browserEnabled (
          lib.genAttrs editorMimeTypes (_: [ "nvim.desktop" ])
          // {
            "application/pdf" = [ "${browser}.desktop" ];
          }
        )
        // officeMimeApplications
        // lib.optionalAttrs (features.apps.enable && features.flatpak.enable) (
          lib.genAttrs photocraftMimeTypes (_: [ "ai.storyteller.photocraft.desktop" ])
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
