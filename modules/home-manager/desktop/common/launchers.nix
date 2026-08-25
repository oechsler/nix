# Desktop Launcher Configuration
#
# Shared pinned applications for KDE and Hyprland.

{ desktop, lib, ... }:
{
  options.desktop.pinnedApps = {
    entries = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = desktop.pinnedApps.entries;
      description = "Pinned dock/taskbar apps as desktop file names (without .desktop suffix)";
    };
    declarative = lib.mkOption {
      type = lib.types.bool;
      default = desktop.pinnedApps.declarative;
      description = "Whether pinned dock/taskbar apps are enforced on every desktop start.";
    };
  };

}
