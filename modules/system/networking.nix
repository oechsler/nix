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
      ipv4.method = "auto";
      ipv6.method = "auto";
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
        };
      };
    }

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

      sops = {
        templates."wifi-env".content = wifiEnvContent;
        secrets = wifiSecrets;
      };
    })
  ];
}
