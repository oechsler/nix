# Gowall Tray Icon Processing
#
# Builds gowall-catppuccinized PNGs for tray icons used in waybar.
# Icons are auto-derived from feature flags (gaming → steam, apps → chat/pass/discord/mumble, tailscale → vpn).
# Papirus icons are SVGs — gowall needs raster input, so we rasterize via rsvg-convert
# before piping through gowall for Catppuccin color conversion.
#
# Toggle icon theming via: catppuccinize.icons.enable
{
  config,
  pkgs,
  lib,
  ...
}:

let
  papirus = pkgs.papirus-icon-theme;
  papirusRoot = "${papirus}/share/icons/Papirus";

  processIcon =
    iconName:
    pkgs.runCommand "gowall-tray-${iconName}"
      {
        nativeBuildInputs = [
          pkgs.librsvg
          pkgs.gowall
        ];
      }
      ''
        svg=$(find ${papirusRoot} -name '${iconName}.svg' -type f | head -1)
        if [ -z "$svg" ]; then
          echo "ERROR: icon '${iconName}' not found in Papirus" >&2
          exit 1
        fi
        ${pkgs.librsvg}/bin/rsvg-convert -b none -f png "$svg" \
          | ${pkgs.gowall}/bin/gowall convert - - -t ${config.gowall.themeJSON} --yes \
          > "$out"
      '';
in
{
  options.gowall.trayIcons = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    readOnly = true;
    description = "Papirus icon names to catppuccinize for waybar tray, auto-derived from feature flags.";
  };

  options.gowall.trayIconPaths = lib.mkOption {
    type = lib.types.attrsOf lib.types.path;
    readOnly = true;
    description = "Map of icon-name → gowall-processed PNG path.";
  };

  config = lib.mkIf (config.catppuccinize.enable && config.catppuccinize.icons.enable) {
    gowall.trayIcons =
      lib.optional config.features.gaming.enable "steam_tray_mono"
      ++ lib.optionals config.features.apps.enable [
        "mumble-indicator"
        "applications-chat-panel"
        "dialog-password-panel"
        "discord-tray"
      ]
      ++ lib.optional config.features.tailscale.enable "network-vpn";

    gowall.trayIconPaths = lib.listToAttrs (
      map (name: {
        inherit name;
        value = processIcon name;
      }) config.gowall.trayIcons
    );
  };
}
