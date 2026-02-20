# Locale Configuration
#
# This module configures system locale, timezone, and keyboard layout.
#
# Configuration:
#   locale.timezone = "Europe/Berlin";  # System timezone
#   locale.language = "de_DE.UTF-8";    # System locale for UI/formats
#   locale.keyboard = "de";             # Console keyboard layout
#
# Applied to:
# - System time (timezone)
# - All locale categories (address, measurement, monetary, etc.)
# - Console keyboard layout
# - Desktop keyboard layout (consumed by Hyprland, KDE)

{ config, pkgs, lib, ... }:

let
  cfg = config.locale;
in
{
  options.locale = {
    timezone = lib.mkOption {
      type = lib.types.str;
      default = "Europe/Berlin";
      description = "Timezone";
    };
    language = lib.mkOption {
      type = lib.types.str;
      default = "de_DE.UTF-8";
      description = "System locale";
    };
    keyboard = lib.mkOption {
      type = lib.types.str;
      default = "de";
      description = "Keyboard layout";
    };
  };

  config = {
    time.timeZone = cfg.timezone;

    i18n.defaultLocale = cfg.language;
    i18n.extraLocaleSettings = {
      LC_ADDRESS = cfg.language;
      LC_IDENTIFICATION = cfg.language;
      LC_MEASUREMENT = cfg.language;
      LC_MONETARY = cfg.language;
      LC_NAME = cfg.language;
      LC_NUMERIC = cfg.language;
      LC_PAPER = cfg.language;
      LC_TELEPHONE = cfg.language;
      LC_TIME = cfg.language;
    };

    console.keyMap = cfg.keyboard;
  };
}
