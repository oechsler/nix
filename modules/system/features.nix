# Feature Toggles Configuration
#
# This module defines global feature toggles consumed by multiple modules.
#
# --- SERVER MODE ---
#
#   features.server = true;                 # Minimal server setup (disables desktop, audio, etc.)
#
# Server mode disables desktop/GUI/audio/bluetooth/wifi/gaming/devtools.
# Encryption and auth (YubiKey/TOTP for sudo/SSH) remain active.
# On a pure server, encryption.unlockMethod should be "tpm2" (auto-unlock).
#
# --- ENCRYPTION ---
#
#   features.encryption.enable = true;  # LUKS disk encryption (default: true)
#   features.encryption.unlockMethod = "tpm2" | "yubikey" | "password";
#
# Controls how LUKS is unlocked at boot:
#   tpm2      — TPM2 auto-unlock (no interaction), default.
#   yubikey   — YubiKey FIDO2 touch, enables auth.yubikey automatically.
#   password  — prompt for LUKS passphrase on every boot.
#
# --- DESKTOP LOGIN ---
#
#   features.desktop.login = "greeter" | "autologin";
#
# Controls SDDM behavior after boot:
#   greeter   — User logs in manually via SDDM, keyring unlocked normally.
#   autologin — SDDM skips login, desktop starts automatically.
#
# --- RECOMMENDED COMBINATIONS ---
#
# YubiKey + Greeter (samuels-pc):
#   encryption.unlockMethod = "yubikey";
#   desktop.login = "greeter";
#   → LUKS unlocked via YubiKey, SDDM shows login, password unlocks keyring.
#
# TPM2 + Greeter (server, laptop without user intervention):
#   encryption.unlockMethod = "tpm2";
#   desktop.login = "greeter";
#   → LUKS auto-unlocks, SDDM shows login, password unlocks keyring.
#
# Password + Autologin (single password, no interaction after boot):
#   encryption.unlockMethod = "password";
#   desktop.login = "autologin";
#   → LUKS password cached by systemd, reused for autologin and keyring.
#   → REQUIRES: LUKS passphrase = user password = keyring password (manual).
#
# --- OTHER OPTIONS ---
#
#   features.desktop.wm = "hyprland" | "kde";  # Window manager (default: hyprland)
#   features.desktop.fileManager = "default" | "terminal";  # Primary file manager
#   features.auth.yubikey.enable = true;        # YubiKey PAM (default: on when unlockMethod = "yubikey")
#   features.auth.totp.enable = true;           # TOTP 2FA (default: true)
#   features.development.enable = true;         # Dev tools (default: true)
#   features.apps.enable = true;                # Desktop apps (default: true)
#

{ config, lib, ... }:

let
  isAutologin = config.features.desktop.login == "autologin";
  hasYubiKey = config.features.auth.yubikey.enable;
  hasTotp = config.features.auth.totp.enable;

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
    desktop.enable = false; # No Hyprland/KDE, SDDM, Firefox, hypr-dock
    apps.enable = false; # No Discord, Spotify, etc.
    development.enable = false; # No dev tools (languages, kubectl, IDEs, etc.)

    # Hardware
    audio.enable = false; # No sound
    bluetooth.enable = false; # No Bluetooth
    wifi.enable = false; # No WiFi (Ethernet only)

    # Software distribution
    flatpak.enable = false; # No Flatpak
    appimage.enable = false; # No AppImage
    gaming.enable = false; # No Steam, etc.
    virtualisation.enable = false; # No Docker/containers

    # Kernel
    kernel = "cachyos-server"; # Server-optimized kernel

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

    impermanence = {
      enable = (lib.mkEnableOption "impermanent root with rollback on boot") // {
        default = true;
      };
      persistPrefix = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        default = if config.features.impermanence.enable then "/persist" else "";
        description = "Path prefix for persistent files. '/persist' when impermanence is active, '' otherwise. Use this for files that must bypass bind-mounts (e.g., pam_oath usersfile).";
      };
      extraPaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Additional paths to persist (beyond feature-based defaults)";
        example = [
          "/var/lib/custom-app"
          "/etc/custom-config"
        ];
      };
    };

    encryption = {
      enable = (lib.mkEnableOption "LUKS full disk encryption") // {
        default = true;
      };
      unlockMethod = lib.mkOption {
        type = lib.types.enum [
          "yubikey"
          "tpm2"
          "password"
        ];
        default = "tpm2";
        description = "How LUKS devices are unlocked at boot.";
      };
    };

    desktop = {
      enable = (lib.mkEnableOption "desktop environment (Hyprland, SDDM, Firefox)") // {
        default = true;
      };
      wm = lib.mkOption {
        type = lib.types.enum [
          "hyprland"
          "kde"
        ];
        default = "hyprland";
        description = "Window manager / desktop environment";
      };
      login = lib.mkOption {
        type = lib.types.enum [
          "greeter"
          "autologin"
        ];
        default = "greeter";
        description = "How the desktop session is entered after boot.";
      };
      fileManager = lib.mkOption {
        type = lib.types.enum [
          "default"
          "terminal"
        ];
        default = "default";
        description = "Primary file manager for the desktop environment";
      };
    };
    hardware = {
      gpu = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum [ "amd" "intel" ]);
        default = null;
        description = "GPU vendor — enables graphics support and the correct VA-API driver for hardware video decoding. AMD also gets 32-bit libs when gaming is enabled.";
      };
    };

    development.enable = (lib.mkEnableOption "development tools") // {
      default = true;
    };
    apps = {
      enable = (lib.mkEnableOption "desktop applications (Discord, Spotify, etc.)") // {
        default = true;
      };
      winboat.enable = lib.mkEnableOption "WinBoat (Windows VM with seamless integration)";
    };
  };

  config = lib.mkMerge [
    # Apply server mode configuration
    (lib.mkIf config.features.server (lib.setAttrByPath [ "features" ] serverModeOptions))

    {
      warnings =
        lib.optional (isAutologin && config.features.encryption.unlockMethod != "password")
          "features.desktop.login = 'autologin' with features.encryption.unlockMethod = '${config.features.encryption.unlockMethod}' can start the session with a locked keyring. Use desktop.login = 'greeter' or encryption.unlockMethod = 'password' if you want to avoid later keyring password prompts."
        ++
          lib.optional (isAutologin && config.features.encryption.unlockMethod == "password")
            "For password autologin, keep LUKS passphrase, user password, and keyring password identical. NixOS cannot enforce this."
        ++
          lib.optional (hasYubiKey && !hasTotp)
            "features.auth.yubikey.enable = true without features.auth.totp.enable = true leaves sudo with no TOTP fallback. If your YubiKey is unavailable, sudo falls through to plain password.";

      assertions = [
        {
          assertion = config.features.encryption.unlockMethod != "yubikey" || hasYubiKey;
          message = "features.encryption.unlockMethod = 'yubikey' requires features.auth.yubikey.enable = true. Set auth.yubikey.enable = true or change encryption.unlockMethod.";
        }
      ];
    }
  ];
}
