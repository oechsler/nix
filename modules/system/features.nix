# Feature Toggles Configuration
#
# This module defines global feature toggles consumed by multiple modules.
#
# --- FORM FACTOR ---
#
#   features.hardware.formFactor = "desktop" | "laptop" | "server";
#
# Determines machine-type-specific behavior:
#
#   "desktop" (default)
#     - Lid switch → ignore (no lid on a desktop)
#     - AMD GPU → runpm=0 (disable GPU runtime PM, prevents resume hangs)
#     - Power key → suspend
#     - Higher idle timeouts (always on AC power)
#
#   "laptop"
#     - Lid switch → suspend on battery, ignore on external power
#     - AMD GPU → NOT disabled (runtime PM keeps battery alive)
#     - Power key → suspend
#     - Lower idle timeouts (battery-conscious)
#
#   "server"
#     - Lid switch → ignore
#     - AMD GPU → runpm=0 (disable GPU runtime PM)
#     - Power key → ignore (accidental shutdown prevention)
#     - power-profiles-daemon disabled (servers don't need dynamic profiles)
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
# YubiKey + Greeter (desktop with YubiKey):
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
#   features.hardware.formFactor = "desktop" | "laptop" | "server"  (default: "desktop")
#   features.hardware.cpu = "amd" | "intel" | null                  (CPU vendor, required for microcode)
#   features.hardware.gpu = "amd" | "intel" | null                  (GPU vendor, required for graphics)
#   features.desktop.wm = "hyprland" | "kde";                       # Window manager (default: hyprland)
#   features.desktop.fileManager = "default" | "terminal";          # Primary file manager
#   features.auth.yubikey.enable = true;        # YubiKey PAM (default: on when unlockMethod = "yubikey")
#   features.auth.totp.enable = true;           # TOTP 2FA (default: true)
#   features.dev.enable = true;                 # Dev tools - languages, IDEs (default: true)
#   features.dev.opencode.enable = true;        # OpenCode AI agent (default: dev.enable)
#   features.ops.enable = true;                 # Ops tools - infra management (default: true)
#   features.ops.pvetui.enable = true;          # Proxmox VE Terminal UI (default: ops.enable)
#   features.ops.kubernetes.enable = true;      # Kubernetes tools & k9s (default: ops.enable)
#   features.apps.enable = true;                # Desktop apps (default: true)
#

{ config, lib, ... }:

let
  isAutologin = config.features.desktop.login == "autologin";
  hasYubiKey = config.features.auth.yubikey.enable;
  hasTotp = config.features.auth.totp.enable;

  # ============================================================================
  # SERVER FORM FACTOR CONFIGURATION
  # ============================================================================
  # What gets disabled when hardware.formFactor = "server"
  #
  # Easy to customize: Just comment out lines you want to keep active,
  # or add new features to disable.
  #
  serverModeConfig = {
    # Desktop & GUI
    desktop.enable = false; # No Hyprland/KDE, SDDM, Firefox, hypr-dock
    apps.enable = false; # No Discord, Spotify, etc.
    dev.enable = false; # No dev tools (languages, IDEs, etc.)
    ops.enable = false; # No ops tools (pvetui, kubernetes, etc.)

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

  isServer = config.features.hardware.formFactor == "server";
in
{
  # Feature toggles consumed by multiple modules.
  # Single-module toggles (gaming, bluetooth, etc.) are defined in their own modules.
  options.features = {
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

    hardware = {
      formFactor = lib.mkOption {
        type = lib.types.enum [
          "desktop"
          "laptop"
          "server"
        ];
        default = "desktop";
        description = ''
          Machine form factor — selects machine-type-specific behavior:

          "desktop"
            - Lid switch → ignore (no lid on a desktop)
            - AMD GPU → runpm=0 (disable GPU runtime PM, prevents resume hangs)
            - Power key → suspend

          "laptop"
            - Lid switch → suspend on battery, ignore on external power
            - AMD GPU → runtime PM enabled (keeps battery alive)
            - Power key → suspend

          "server"
            - Lid switch → ignore
            - AMD GPU → runpm=0 (disable GPU runtime PM)
            - Power key → ignore (accidental shutdown prevention)
            - power-profiles-daemon disabled (servers don't need dynamic profiles)
        '';
      };

      cpu = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.enum [
            "amd"
            "intel"
          ]
        );
        default = null;
        description = "CPU vendor — enables the correct microcode update package (security patches from AMD/Intel loaded at early boot).";
      };
      gpu = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.enum [
            "amd"
            "intel"
          ]
        );
        default = null;
        description = "GPU vendor — enables graphics support and the correct VA-API driver for hardware video decoding. AMD also gets 32-bit libs when gaming is enabled. NVIDIA is not supported.";
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

    dev = {
      enable = (lib.mkEnableOption "development tools") // {
        default = true;
      };
      opencode = {
        enable = (lib.mkEnableOption "OpenCode AI coding agent") // {
          default = config.features.dev.enable;
        };
      };
      jetbrains = {
        enable = (lib.mkEnableOption "JetBrains IDEs (GoLand, RustRover)") // {
          default = config.features.dev.enable;
        };
      };
      dbeaver = {
        enable = (lib.mkEnableOption "DBeaver database GUI") // {
          default = config.features.dev.enable;
        };
      };
    };

    ops = {
      enable = (lib.mkEnableOption "operations tools") // {
        default = true;
      };
      pvetui = {
        enable = (lib.mkEnableOption "pvetui (Proxmox VE Terminal UI)") // {
          default = config.features.ops.enable;
        };
        profiles = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                name = lib.mkOption {
                  type = lib.types.str;
                  description = "Profile name (used as identifier and sops secret path)";
                };
                addr = lib.mkOption {
                  type = lib.types.str;
                  description = "Proxmox API URL (e.g., https://proxmox:8006)";
                };
                user = lib.mkOption {
                  type = lib.types.str;
                  default = config.user.name;
                  description = "Proxmox username";
                };
                realm = lib.mkOption {
                  type = lib.types.str;
                  default = "sso";
                  description = "Authentication realm";
                };
                tokenId = lib.mkOption {
                  type = lib.types.str;
                  default = "pvetui";
                  description = "API token ID";
                };
                insecure = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                  description = "Skip TLS verification";
                };
                sshUser = lib.mkOption {
                  type = lib.types.str;
                  default = config.user.name;
                  description = "SSH username for node access";
                };
                vmSshUser = lib.mkOption {
                  type = lib.types.str;
                  default = config.user.name;
                  description = "SSH username for VM access";
                };
                sshKeyfile = lib.mkOption {
                  type = lib.types.str;
                  default = "~/.ssh/id_ed25519";
                  description = "SSH private key path";
                };
              };
            }
          );
          default = [ ];
          description = "List of Proxmox server profiles for pvetui";
        };
        defaultProfile = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Default profile name (empty = first profile)";
        };
      };
      kubernetes = {
        enable = (lib.mkEnableOption "Kubernetes tools and k9s") // {
          default = config.features.ops.enable;
        };
        clusters = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                name = lib.mkOption {
                  type = lib.types.str;
                  description = "Cluster name (used as context name)";
                };
                server = lib.mkOption {
                  type = lib.types.str;
                  description = "Kubernetes API server URL (e.g., https://k3s.example.com:6443)";
                };
                caData = lib.mkOption {
                  type = lib.types.str;
                  description = "Base64-encoded CA certificate for the cluster";
                };
                namespace = lib.mkOption {
                  type = lib.types.str;
                  default = "default";
                  description = "Default namespace for this context";
                };
                user = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = "oidc";
                  description = "User name for this context (null for no user entry)";
                };
                oidc = {
                  issuerUrl = lib.mkOption {
                    type = lib.types.str;
                    description = "OIDC issuer URL";
                  };
                  clientId = lib.mkOption {
                    type = lib.types.str;
                    description = "OIDC client ID";
                  };
                  extraScopes = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [
                      "email"
                      "groups"
                    ];
                    description = "Additional OIDC scopes to request";
                  };
                };
              };
            }
          );
          default = [ ];
          description = "List of Kubernetes clusters with OIDC authentication";
        };
        defaultContext = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Default Kubernetes context (empty = first cluster)";
        };
      };
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
    (lib.mkIf isServer (lib.setAttrByPath [ "features" ] serverModeOptions))

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
        {
          assertion = !config.features.encryption.enable || config.boot.initrd.luks.devices != { };
          message = "features.encryption.enable = true requires a LUKS device in the host's disko.nix. If the host uses no encryption, set features.encryption.enable = false.";
        }
      ];
    }
  ];
}
