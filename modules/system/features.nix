# Feature Toggles Configuration
#
# This module defines global feature toggles consumed by multiple modules.
#
# --- FORM FACTOR ---
#
#   features.hardware.formFactor = "desktop" | "laptop";
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
# TPM2 + Greeter (laptop without user intervention):
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
# --- FEATURE REFERENCE ---
#
# Feature options are defined below in the same order as the configuration
# layers: hardware, boot/security, desktop, development/operations, and apps.
# Detailed defaults and examples live in docs/CONFIG.md.
#

{ config, lib, ... }:

let
  isAutologin = config.features.desktop.login == "autologin";
  hasYubiKey = config.features.auth.yubikey.enable;
  hasTotp = config.features.auth.totp.enable;

in
{
  # Feature toggles consumed by multiple modules.
  # Single-module toggles (gaming, bluetooth, etc.) are defined in their own modules.
  options.features = {
    hardware = {
      formFactor = lib.mkOption {
        type = lib.types.enum [
          "desktop"
          "laptop"
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
      enable = (lib.mkEnableOption "desktop environment (Hyprland, SDDM, LibreWolf)") // {
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
      browser = {
        enable = (lib.mkEnableOption "default web browser") // {
          default = true;
        };
        type = lib.mkOption {
          type = lib.types.enum [
            "librewolf"
            "firefox"
          ];
          default = "librewolf";
          description = "Default web browser";
        };
        newTabPage = lib.mkOption {
          type = lib.types.str;
          default = "https://dash.at.oechsler.it";
          description = "URL used by the managed new-tab page";
        };
        searchEngine = lib.mkOption {
          type = lib.types.str;
          default = "ddg";
          description = "Default browser search engine identifier";
        };
        cookieAllowlist = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Additional sites allowed to keep first-party cookies and sessions";
        };
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
                sshAddr = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = "SSH hostname (if different from API addr hostname)";
                };
                groups = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                  description = "List of groups this profile belongs to (for Group Mode)";
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
          description = "Default profile or group name (can be a profile name or a group name)";
        };
        groups = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                mode = lib.mkOption {
                  type = lib.types.enum [
                    "aggregate"
                    "cluster"
                  ];
                  default = "aggregate";
                  description = "Group mode: 'aggregate' combines resources, 'cluster' is active/passive failover";
                };
              };
            }
          );
          default = { };
          description = "Settings for each group (mode: aggregate or cluster)";
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

    virtualisation = {
      enable = (lib.mkEnableOption "container and virtualisation support") // {
        default = true;
      };
      container.enable = (lib.mkEnableOption "container support") // {
        default = true;
      };
      vm.enable = (lib.mkEnableOption "QEMU/KVM virtual machines") // {
        default = true;
      };
    };

    apps = {
      enable = (lib.mkEnableOption "desktop applications (Discord, Spotify, etc.)") // {
        default = true;
      };

      mumble = {
        enable = (lib.mkEnableOption "Mumble voice chat") // {
          default = true;
        };
        username = lib.mkOption {
          type = lib.types.str;
          default = config.user.name;
          description = "Default Mumble username.";
        };
        playMuteCue = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Play a sound when Mumble is muted or unmuted.";
        };
        channelExpansionMode = lib.mkOption {
          type = lib.types.str;
          default = "AllChannels";
          description = "Mumble channel expansion mode.";
        };
        disablePublicServerList = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Disable Mumble's public server list.";
        };
        autoConnectToLastServer = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Automatically connect to the last Mumble server.";
        };
        reconnectAutomatically = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Reconnect automatically after a connection loss.";
        };
        hideInTray = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Keep Mumble in the system tray instead of the taskbar.";
        };
        quitBehavior = lib.mkOption {
          type = lib.types.enum [
            "AlwaysAsk"
            "AskWhenConnected"
            "AlwaysMinimize"
            "MinimizeWhenConnected"
            "AlwaysQuit"
          ];
          default = "AlwaysMinimize";
          description = "What Mumble does when its window is closed.";
        };
        serverFilterMode = lib.mkOption {
          type = lib.types.enum [
            "ShowPopulated"
            "ShowReachable"
            "ShowAll"
          ];
          default = "ShowAll";
          description = "Which servers are shown in the Mumble server list.";
        };
        servers = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                name = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = "Optional display name; defaults to the server hostname.";
                };
                host = lib.mkOption {
                  type = lib.types.str;
                  description = "Mumble server hostname.";
                };
                port = lib.mkOption {
                  type = lib.types.port;
                  default = 64738;
                };
                username = lib.mkOption {
                  type = lib.types.str;
                  default = config.features.apps.mumble.username;
                };
              };
            }
          );
          default = [ ];
          description = "Mumble servers shown in the server list.";
        };
      };
    };
  };

  config = lib.mkMerge [
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
