# Deck Integration (Decky Loader + CSS Loader + Catppuccin)
#
# This module provides declarative Steam Deck UI theming for Steam Machine mode.
# It integrates Jovian-NixOS's decky-loader with the CSS Loader plugin and
# Catppuccin theme.
#
# Requirements:
#   - features.gaming.steamMachine.enable = true
#   - A Steam Machine session (gamescope-only steam)
#
# Configuration:
#   features.gaming.steamMachine.catppuccin.enable = true;
#   features.gaming.steamMachine.catppuccin.flavor = "mocha";    # default
#   features.gaming.steamMachine.catppuccin.accent = "lavender";  # default
#
# How it works:
#   1. Enables Jovian-NixOS decky-loader (systemd service, decky user)
#   2. Installs CSS Loader plugin at /var/lib/decky-loader/plugins/SDH-CssLoader/
#   3. Installs Catppuccin theme at /var/lib/decky-loader/themes/Catppuccin/
#   4. Creates CEF debugging flag (~/.steam/steam/.cef-enable-remote-debugging)
#   5. CSS Loader must be enabled via Decky UI to activate the theme

{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.features.gaming.steamMachine.catppuccin;
  steamMachineCfg = config.features.gaming.steamMachine;
  stateDir = "/var/lib/decky-loader";
  deckyUser = "decky";

  cssLoader = pkgs.callPackage ../../packages/css-loader.nix { };
  catppuccinDeck = pkgs.callPackage ../../packages/catppuccin-deck.nix { };
in
{
  options.features.gaming.steamMachine.catppuccin = {
    enable = lib.mkEnableOption "Catppuccin theme for Steam Deck UI in Steam Machine mode";
    flavor = lib.mkOption {
      type = lib.types.enum [
        "latte"
        "frappe"
        "macchiato"
        "mocha"
      ];
      default = "mocha";
      description = "Catppuccin flavor";
    };
    accent = lib.mkOption {
      type = lib.types.enum [
        "rosewater"
        "flamingo"
        "pink"
        "mauve"
        "red"
        "maroon"
        "peach"
        "yellow"
        "green"
        "teal"
        "sky"
        "sapphire"
        "blue"
        "lavender"
      ];
      default = "lavender";
      description = "Catppuccin accent color";
    };
  };

  config = lib.mkIf (steamMachineCfg.enable && cfg.enable) {
    jovian.decky-loader = {
      enable = true;
      package = inputs.jovian-nixos.legacyPackages.${pkgs.system}.decky-loader;
    };

    # Directories for plugin and theme (mutable - CSS Loader writes config to them)
    systemd.tmpfiles.rules = [
      "d ${stateDir}/plugins/SDH-CssLoader 0750 ${deckyUser} ${deckyUser} - -"
      "d ${stateDir}/themes/Catppuccin 0750 ${deckyUser} ${deckyUser} - -"
      "d ${stateDir}/themes/Catppuccin/flavors 0750 ${deckyUser} ${deckyUser} - -"
      "d ${stateDir}/themes/Catppuccin/tweaks 0750 ${deckyUser} ${deckyUser} - -"
      "f+ /home/${config.user.name}/.steam/steam/.cef-enable-remote-debugging 0644 ${config.user.name} users - -"
    ];

    systemd.services.install-deck-theme = {
      description = "Install Catppuccin Deck theme and CSS Loader plugin files";
      wantedBy = [ "multi-user.target" ];
      before = [ "decky-loader.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        plugin_dir="${stateDir}/plugins/SDH-CssLoader"
        theme_dir="${stateDir}/themes/Catppuccin"

        mkdir -p "$plugin_dir" "$theme_dir/flavors" "$theme_dir/tweaks"

        for f in ${cssLoader}/*; do
          bn=$(basename "$f")
          if [ -d "$f" ]; then
            cp -r --no-preserve=mode "$f" "$plugin_dir/$bn"
          else
            cp --no-preserve=mode "$f" "$plugin_dir/$bn"
          fi
        done

        cp --no-preserve=mode ${catppuccinDeck}/theme.json "$theme_dir/"
        cp --no-preserve=mode ${catppuccinDeck}/shared.css "$theme_dir/"
        cp --no-preserve=mode ${catppuccinDeck}/svg.css "$theme_dir/"
        cp --no-preserve=mode ${catppuccinDeck}/keyboard.css "$theme_dir/"
        cp --no-preserve=mode ${catppuccinDeck}/flavors/*.css "$theme_dir/flavors/"
        cp --no-preserve=mode ${catppuccinDeck}/tweaks/*.css "$theme_dir/tweaks/"

        chown -R ${deckyUser}:${deckyUser} "$plugin_dir" "$theme_dir"
      '';
    };
  };
}
