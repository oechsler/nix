# Home Manager activation hooks, packages, and session-wide defaults.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = {
    # Reduce default stop timeout for user session.
    xdg.configFile."systemd/user.conf".text = ''
      [Manager]
      DefaultTimeoutStopSec=10s
    '';

    home = {
      activation = {
        removeLegacyHyprlandConfig = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
          rm -f "${config.xdg.configHome}/hypr/hyprland.conf"
        '';

        # Remove a stale Mumble mask before Home Manager owns the user unit.
        removeLegacyMumbleMask = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
          ${config.programs.mumble.removeLegacyMask}
        '';
      };

      packages = [
        pkgs.brightnessctl
        pkgs.ddcutil
        pkgs.playerctl
        pkgs.hyprshot
        pkgs.satty
        pkgs.wl-clipboard
        pkgs.cliphist
        # GTK portal must be in the same profile as the Hyprland portal,
        # otherwise xdg-desktop-portal won't find gtk.portal and the
        # Settings interface (dark mode, color-scheme) won't work.
        pkgs.xdg-desktop-portal-gtk
      ];
    };
  };
}
