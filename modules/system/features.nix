# Feature Toggles Configuration
#
# This module defines global feature toggles consumed by multiple modules.
#
# Server Mode:
#   features.server = true;  # Minimal server setup (see details below)
#
# Desktop:
#   features.desktop.enable = true;         # Desktop environment (default: true)
#   features.desktop.wm = "hyprland";       # Window manager: hyprland or kde
#   features.desktop.dock.enable = true;    # hypr-dock (default: true, Hyprland only)
#
# Development:
#   features.development.enable = true;     # Dev tools & languages (default: true)
#   features.development.gui.enable = true; # GUI dev tools (default: true)
#
# Apps:
#   features.apps.enable = true;            # Desktop apps (Discord, Spotify, etc.)
#
# Server mode disables:
# - Desktop environment (Hyprland/KDE, SDDM, Firefox, hypr-dock)
# - Audio, Bluetooth, WiFi
# - Gaming (Steam)
# - GUI apps (Discord, Spotify, etc.)
# - Development tools (languages, kubectl, VS Code, JetBrains, etc.)
# - Flatpak, AppImage
#
# Server mode enables:
# - CachyOS server-optimized kernel
# - Networking (Ethernet, Tailscale)
# - Basic CLI tools (git, htop, etc.)
# - SSH

{ config, lib, ... }:

let
  # ============================================================================
  # SERVER MODE CONFIGURATION
  # ============================================================================
  # What gets disabled when features.server = true
  #
  # Easy to customize: Just comment out lines you want to keep active,
  # or add new features to disable.
  #
  serverModeConfig = {
    # Desktop & GUI
    desktop.enable = false;                # No Hyprland/KDE, SDDM, Firefox, hypr-dock
    apps.enable = false;                   # No Discord, Spotify, etc.
    development.enable = false;            # No dev tools (languages, kubectl, VS Code, etc.)

    # Hardware
    audio.enable = false;                  # No sound
    bluetooth.enable = false;              # No Bluetooth
    wifi.enable = false;                   # No WiFi (Ethernet only)

    # Software distribution
    flatpak.enable = false;                # No Flatpak
    appimage.enable = false;               # No AppImage
    gaming.enable = false;                 # No Steam, etc.

    # Kernel
    kernel = "cachyos-server";             # Server-optimized kernel

    # What STAYS active in server mode:
    # - Networking (Ethernet, DNS, mDNS)
    # - Tailscale VPN
    # - Basic CLI tools (git, htop, etc.)
    # - SSH
    # - CachyOS server kernel
  };

  # Convert the config map to NixOS options
  # This uses lib.mkDefault so you can override individual settings
  serverModeOptions = lib.mapAttrs (_: value: lib.mkDefault value) serverModeConfig;
in
{
  # Feature toggles consumed by multiple modules.
  # Single-module toggles (gaming, bluetooth, etc.) are defined in their own modules.
  options.features = {
    server = lib.mkEnableOption "server mode (disables desktop, audio, bluetooth, gaming, etc.)";
    desktop = {
      enable = (lib.mkEnableOption "desktop environment (Hyprland, SDDM, Firefox)") // { default = true; };
      wm = lib.mkOption {
        type = lib.types.enum [ "hyprland" "kde" ];
        default = "hyprland";
        description = "Window manager / desktop environment";
      };
      dock = {
        enable = (lib.mkEnableOption "hypr-dock (application dock for Hyprland)") // { default = true; };
      };
    };
    development = {
      enable = (lib.mkEnableOption "development tools (languages, CLI tools, K8s)") // { default = true; };
      gui.enable = (lib.mkEnableOption "GUI development tools (VS Code, JetBrains, DBeaver)") // { default = true; };
    };
    apps = {
      enable = (lib.mkEnableOption "desktop applications (Discord, Spotify, etc.)") // { default = true; };
    };
  };

  # Apply server mode configuration
  config = lib.mkIf config.features.server (
    lib.setAttrByPath [ "features" ] serverModeOptions
  );
}
