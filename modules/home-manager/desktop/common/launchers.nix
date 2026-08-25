# Desktop Launcher Configuration
#
# Shared pinned applications for KDE and Hyprland.

{
  features,
  lib,
  ...
}:

let
  isKde = features.desktop.wm == "kde";
  usesTerminalFileManager = features.desktop.fileManager == "terminal";
  browserEnabled = features.desktop.browser.enable;
  browser = features.desktop.browser.type;
in
{
  options.desktop.pinnedApps = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "Pinned dock/taskbar apps as desktop file names (without .desktop suffix)";
  };

  config.desktop.pinnedApps =
    lib.optional browserEnabled browser
    ++ lib.optional usesTerminalFileManager "yazi"
    ++ lib.optional (!usesTerminalFileManager) (
      if isKde then "org.kde.dolphin" else "org.gnome.Nautilus"
    )
    ++ [
      "kitty"
    ]
    ++ lib.optionals features.dev.enable [
      "nvim"
    ]
    ++ lib.optionals features.apps.enable [
      "obsidian"
    ]
    ++ lib.optionals features.gaming.enable [
      "steam"
    ]
    ++ lib.optionals features.apps.enable [
      "vesktop"
    ]
    ++ lib.optional (features.apps.enable && features.apps.mumble.enable) "info.mumble.Mumble"
    ++ lib.optionals features.apps.enable [
      "spotify"
    ];
}
