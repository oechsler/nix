# Network Configuration
#
# This module configures:
# 1. Base networking (NetworkManager, DNS, mDNS)
# 2. WiFi profiles with iwd backend
# 3. Ethernet connection profile
# 4. Policy-based routing for dual interfaces (Hyprland only)
# 5. Tailscale VPN (optional)
#
# Configuration options:
#   features.wifi.enable = true;              # Enable WiFi (default: true)
#   features.wifi.networks = [ "home" ];      # WiFi networks to manage (default: ["home"])
#   features.tailscale.enable = true;         # Enable Tailscale VPN (default: true)
#
# WiFi credentials are stored in SOPS secrets:
#   wifi/<name>/ssid - SSID of the network
#   wifi/<name>/psk  - Pre-shared key (password)

{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.features.wifi;
  tailscaleCfg = config.features.tailscale;

  # WiFi connection profiles with credentials from SOPS
  wifiProfiles = lib.listToAttrs (
    map (name: {
      name = "wifi-${name}";
      value = {
        connection = {
          id = "\${WIFI_${lib.toUpper name}_SSID}";
          type = "wifi";
          autoconnect = true;
        };
        wifi = {
          mode = "infrastructure";
          ssid = "\${WIFI_${lib.toUpper name}_SSID}";
        };
        wifi-security = {
          auth-alg = "open";
          key-mgmt = "wpa-psk";
          psk = "\${WIFI_${lib.toUpper name}_PSK}";
        };
        ipv4 = {
          method = "auto";
          route-metric = 600; # Lower priority than Ethernet (600 > 100)
        };
        ipv6 = {
          method = "auto";
          route-metric = 600;
        };
      };
    }) cfg.networks
  );

  # Environment file with WiFi credentials for NetworkManager
  wifiEnvContent = lib.concatMapStringsSep "\n" (name: ''
    WIFI_${lib.toUpper name}_SSID=${config.sops.placeholder."wifi/${name}/ssid"}
    WIFI_${lib.toUpper name}_PSK=${config.sops.placeholder."wifi/${name}/psk"}'') cfg.networks;

  # SOPS secrets for WiFi credentials
  wifiSecrets = lib.listToAttrs (
    lib.flatten (
      map (name: [
        {
          name = "wifi/${name}/ssid";
          value = { };
        }
        {
          name = "wifi/${name}/psk";
          value = { };
        }
      ]) cfg.networks
    )
  );
in
{
  #===========================
  # Options
  #===========================

  options.features = {
    wifi.enable = (lib.mkEnableOption "WiFi with managed network profiles") // {
      default = true;
    };
    wifi.networks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "home" ];
      description = "WiFi network names to manage — each needs wifi/<name>/ssid and wifi/<name>/psk SOPS secrets";
    };
    tailscale.enable = (lib.mkEnableOption "Tailscale VPN") // {
      default = true;
    };
  };

  #===========================
  # Configuration
  #===========================

  config = lib.mkMerge [

    #---------------------------
    # 1. Base Networking
    #---------------------------
    {
      networking.networkmanager.enable = true;
      networking.networkmanager.wifi.backend = "iwd";
      networking.wireless.iwd.enable = true;

      # systemd-resolved for DNS
      services.resolved = {
        enable = true;
        settings.Resolve = {
          DNSSEC = "allow-downgrade";
          Domains = [ "~." ];
          MulticastDNS = false;
        };
      };

      # Avahi for mDNS (.local domain resolution)
      services.avahi = {
        enable = true;
        nssmdns4 = true;
        openFirewall = true;
        publish = {
          enable = true;
          addresses = true;
        };
      };

      environment.systemPackages = with pkgs; [
        avahi # mDNS tools (avahi-browse, etc.)
        iwd # WiFi management CLI (iwctl)
      ];
    }

    #---------------------------
    # 2. WiFi Auto-Disconnect (Hyprland only)
    #---------------------------
    # KDE Plasma handles network priority via plasma-nm, so we only configure this for Hyprland
    #
    # Strategy: When Ethernet comes up, disconnect WiFi immediately
    # This avoids dual-interface routing complexity and ensures consistent network behavior
    (lib.mkIf (config.features.desktop.enable && config.features.desktop.wm == "hyprland") {

      # Ethernet connection profile with basic priority settings
      networking.networkmanager.ensureProfiles.profiles.ethernet-default = {
        connection = {
          id = "Ethernet";
          type = "ethernet";
          autoconnect = true;
          autoconnect-priority = 999;
        };
        ipv4 = {
          method = "auto";
          route-metric = 100; # Higher priority (lower number = higher priority)
        };
        ipv6 = {
          method = "auto";
          route-metric = 100;
        };
      };

      # NetworkManager dispatcher script: Disconnect WiFi when Ethernet comes up
      # Dispatcher scripts run on interface state changes (up, down, connectivity-change, etc.)
      # This ensures instant response and works correctly after suspend/resume
      networking.networkmanager.dispatcherScripts = [
        {
          source = pkgs.writeShellScript "wifi-auto-disconnect" ''
            # Arguments from NetworkManager dispatcher:
            # $1 = interface name (e.g., "enp5s0")
            # $2 = action (up, down, connectivity-change, etc.)

            INTERFACE=$1
            ACTION=$2

            # Only act on Ethernet interfaces
            if [[ "$INTERFACE" != enp* && "$INTERFACE" != eth* && "$INTERFACE" != en* ]]; then
              exit 0
            fi

            # When Ethernet comes up, disconnect all active WiFi connections
            if [ "$ACTION" = "up" ]; then
              logger "NetworkManager dispatcher: Ethernet $INTERFACE is up, disconnecting WiFi"

              # Get all active WiFi connections (type is "802-11-wireless")
              WIFI_CONNECTIONS=$(${pkgs.networkmanager}/bin/nmcli -t -f NAME,TYPE,DEVICE connection show --active | grep ':802-11-wireless:' | cut -d: -f1)

              # Disconnect each WiFi connection
              if [ -n "$WIFI_CONNECTIONS" ]; then
                while IFS= read -r conn; do
                  logger "NetworkManager dispatcher: Disconnecting WiFi connection '$conn'"
                  ${pkgs.networkmanager}/bin/nmcli connection down "$conn" || true
                done <<< "$WIFI_CONNECTIONS"
              else
                logger "NetworkManager dispatcher: No active WiFi connections found"
              fi
            fi
          '';
          type = "basic";
        }
      ];
    })

    #---------------------------
    # 3. WiFi Disabled
    #---------------------------
    (lib.mkIf (!cfg.enable) {
      networking.networkmanager.wifi.powersave = false;
      networking.networkmanager.unmanaged = [ "type:wifi" ];
    })

    #---------------------------
    # 4. Tailscale VPN
    #---------------------------
    (lib.mkIf tailscaleCfg.enable {
      services.tailscale.enable = true;

      environment.systemPackages = [
        # Helper script for initial Tailscale setup
        (pkgs.writeShellScriptBin "tailscale-init" ''
          set -e
          echo "Starting Tailscale login..."
          sudo tailscale up --accept-routes --accept-dns
          echo "Setting operator to ${config.user.name}..."
          sudo tailscale set --operator=${config.user.name}
          echo "Done! Tailscale is ready."
          tailscale status
        '')
      ]
      ++ lib.optionals config.features.desktop.enable [
        pkgs.trayscale # System tray applet for Tailscale
      ];
    })

    #---------------------------
    # 5. WiFi Profiles
    #---------------------------
    (lib.mkIf cfg.enable {
      # Create NetworkManager connection profiles for configured WiFi networks
      networking.networkmanager.ensureProfiles = {
        environmentFiles = [ config.sops.templates."wifi-env".path ];
        profiles = wifiProfiles;
      };

      # Don't fail if SOPS key doesn't exist (e.g., fresh install without secrets)
      systemd.services.NetworkManager-ensure-profiles = {
        after = [ "sops-install-secrets.service" ];
        unitConfig.ConditionPathExists = config.sops.age.keyFile;
      };

      # Write iwd profile files for known networks
      # Why: iwd profiles make networks visible in tools like impala
      # Note: iwd requires hex-encoded filenames for SSIDs with special characters
      #       Format: =<hex>.psk (e.g., =4f656368736c657221426f78.psk for "Oechsler!Box")
      systemd.services.iwd-profiles = {
        wantedBy = [ "network-pre.target" ];
        after = [ "sops-install-secrets.service" ];
        before = [ "iwd.service" ];
        unitConfig.ConditionPathExists = config.sops.age.keyFile;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = lib.concatMapStringsSep "\n" (
          name:
          let
            ssidPath = config.sops.secrets."wifi/${name}/ssid".path;
            pskPath = config.sops.secrets."wifi/${name}/psk".path;
          in
          ''
            # Read SSID and convert to hex for filename
            ssid=$(cat ${ssidPath})
            ssid_hex=$(printf '%s' "$ssid" | od -An -tx1 | tr -d ' \n')
            mkdir -p /var/lib/iwd

            # Remove old non-hex-encoded files (from before we fixed the encoding)
            rm -f "/var/lib/iwd/$ssid.psk"

            # Write iwd profile with hex-encoded filename
            printf '[Security]\nPassphrase=%s\n' "$(cat ${pskPath})" \
              > "/var/lib/iwd/=$ssid_hex.psk"
            chmod 0600 "/var/lib/iwd/=$ssid_hex.psk"
          ''
        ) cfg.networks;
      };

      # SOPS secrets for WiFi credentials
      sops = {
        templates."wifi-env".content = wifiEnvContent;
        secrets = wifiSecrets;
      };
    })
  ];
}
