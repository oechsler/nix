{ config, lib, features, ... }:

let
  cfg = config.autostart;
  isKde = features.desktop.wm == "kde";
  slug = app: builtins.replaceStrings [ " " ] [ "-" ] (lib.toLower app.name);
in
{
  options.autostart.apps = lib.mkOption {
    type = lib.types.listOf (lib.types.submodule {
      options = {
        name = lib.mkOption { type = lib.types.str; description = "Human-readable application name"; };
        exec = lib.mkOption { type = lib.types.str; description = "Command to execute"; };
      };
    });
    default = [];
    description = "Applications to start on login (works on both Hyprland and KDE)";
  };

  config = {
    autostart.apps =
      [
        { name = "Bitwarden"; exec = "bitwarden"; }
        { name = "Vesktop"; exec = "vesktop --start-minimized"; }
        { name = "CoolerControl"; exec = "coolercontrol"; }
      ]
      # Nextcloud manages its own XDG autostart under KDE; Hyprland needs exec-once
      ++ lib.optionals (!isKde) [
        { name = "Nextcloud"; exec = "nextcloud --background"; }
      ]
      ++ lib.optionals features.apps.enable [
        { name = "Pika Backup Monitor"; exec = "pika-backup-monitor"; }
      ]
      ++ lib.optionals (features.apps.enable && !isKde) [
        { name = "Spotify"; exec = "spotify"; }
      ]
      ++ lib.optionals features.development.enable [
        { name = "JetBrains Toolbox"; exec = "jetbrains-toolbox --minimize"; }
      ]
      ++ lib.optionals features.tailscale.enable [
        { name = "Trayscale"; exec = "bash -c 'sleep 3 && trayscale --hide-window'"; }
      ]
      ++ lib.optionals features.gaming.enable [
        { name = "Steam"; exec = "steam -silent"; }
      ]
      ++ [
        { name = "Beeper"; exec = "bash -c 'f=$(ls ~/Applications/Beeper-*.AppImage 2>/dev/null | head -1) && [ -n \"$f\" ] && exec \"$f\"'"; }
      ];

    # KDE — generate XDG autostart .desktop entries
    xdg.configFile = lib.mkIf isKde (builtins.listToAttrs (map (app: {
      name = "autostart/${slug app}.desktop";
      value.text = ''
        [Desktop Entry]
        Type=Application
        Name=${app.name}
        Exec=${app.exec}
      '';
    }) cfg.apps));
  };
}
