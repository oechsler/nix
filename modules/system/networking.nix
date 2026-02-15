{ config, pkgs, lib, ... }:

let
  cfg = config.features.wifi;
  tailscaleCfg = config.features.tailscale;
  wifiNetworks = [ "home" ];

  wifiProfiles = lib.listToAttrs (map (name: {
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
        route-metric = 600;  # Lower priority than Ethernet
      };
      ipv6 = {
        method = "auto";
        route-metric = 600;
      };
    };
  }) wifiNetworks);

  wifiEnvContent = lib.concatMapStringsSep "\n" (name: ''
    WIFI_${lib.toUpper name}_SSID=${config.sops.placeholder."wifi/${name}/ssid"}
    WIFI_${lib.toUpper name}_PSK=${config.sops.placeholder."wifi/${name}/psk"}'') wifiNetworks;

  wifiSecrets = lib.listToAttrs (lib.flatten (map (name: [
    { name = "wifi/${name}/ssid"; value = {}; }
    { name = "wifi/${name}/psk"; value = {}; }
  ]) wifiNetworks));
in
{
  options.features = {
    wifi.enable = (lib.mkEnableOption "WiFi with managed network profiles") // { default = true; };
    tailscale.enable = (lib.mkEnableOption "Tailscale VPN") // { default = true; };
  };

  config = lib.mkMerge [
    {
      networking.networkmanager.enable = true;

      services.resolved = {
        enable = true;
        settings.Resolve = {
          DNSSEC = "allow-downgrade";
          Domains = [ "~." ];
          MulticastDNS = false;
        };
      };

      services.avahi = {
        enable = true;
        nssmdns4 = true;
        openFirewall = true;
        publish = {
          enable = true;
          addresses = true;
        };
      };

      environment.systemPackages = with pkgs; [ avahi ];
    }

    # Automatic WiFi management for Hyprland only
    # KDE Plasma has plasma-nm which handles interface priorities better
    (lib.mkIf (config.features.desktop.enable && config.features.desktop.wm == "hyprland") {
      networking.networkmanager.dispatcherScripts = [{
        source = pkgs.writeText "10-auto-wifi-management" ''
          #!/bin/sh
          interface="$1"
          status="$2"

          case "$interface" in
            en*|eth*)
              if [ "$status" = "up" ]; then
                # Ethernet connected - disable all WiFi connections
                logger "NetworkManager: Ethernet $interface up, disabling WiFi"
                for conn in $(${pkgs.networkmanager}/bin/nmcli -t -f NAME,TYPE connection show | ${pkgs.gnugrep}/bin/grep ':802-11-wireless$' | ${pkgs.coreutils}/bin/cut -d: -f1); do
                  ${pkgs.networkmanager}/bin/nmcli connection down "$conn" 2>/dev/null || true
                done
              elif [ "$status" = "down" ]; then
                # Ethernet disconnected - enable WiFi and reconnect
                logger "NetworkManager: Ethernet $interface down, enabling WiFi"
                ${pkgs.networkmanager}/bin/nmcli radio wifi on 2>/dev/null || true

                # Give WiFi radio a moment to come up
                ${pkgs.coreutils}/bin/sleep 1

                # Reconnect to WiFi networks with autoconnect enabled
                for conn in $(${pkgs.networkmanager}/bin/nmcli -t -f NAME,TYPE,AUTOCONNECT connection show | ${pkgs.gnugrep}/bin/grep ':802-11-wireless:yes$' | ${pkgs.coreutils}/bin/cut -d: -f1); do
                  logger "NetworkManager: Reconnecting to WiFi network: $conn"
                  ${pkgs.networkmanager}/bin/nmcli connection up "$conn" 2>/dev/null || true
                done
              fi
              ;;
          esac
        '';
        type = "basic";
      }];
    })

    (lib.mkIf (!cfg.enable) {
      networking.networkmanager.wifi.powersave = false;
      networking.networkmanager.unmanaged = [ "type:wifi" ];
    })

    (lib.mkIf tailscaleCfg.enable {
      services.tailscale.enable = true;

      environment.systemPackages = [
        (pkgs.writeShellScriptBin "tailscale-init" ''
          set -e
          echo "Starting Tailscale login..."
          sudo tailscale up --accept-routes --accept-dns
          echo "Setting operator to ${config.user.name}..."
          sudo tailscale set --operator=${config.user.name}
          echo "Done! Tailscale is ready."
          tailscale status
        '')
      ] ++ lib.optionals config.features.desktop.enable [
        pkgs.trayscale
      ];
    })

    (lib.mkIf cfg.enable {
      networking.networkmanager.ensureProfiles = {
        environmentFiles = [ config.sops.templates."wifi-env".path ];
        profiles = wifiProfiles;
      };

      # Skip gracefully if SOPS key doesn't exist (fresh install)
      systemd.services.NetworkManager-ensure-profiles = {
        after = [ "sops-install-secrets.service" ];
        unitConfig.ConditionPathExists = config.sops.age.keyFile;
      };

      sops = {
        templates."wifi-env".content = wifiEnvContent;
        secrets = wifiSecrets;
      };
    })
  ];
}
