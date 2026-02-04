{ config, pkgs, lib, ... }:

let
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
  networking.networkmanager = {
    enable = true;

    ensureProfiles = {
      environmentFiles = [ config.sops.templates."wifi-env".path ];
      profiles = wifiProfiles;
    };
  };

  sops = {
    templates."wifi-env".content = wifiEnvContent;
    secrets = wifiSecrets;
  };

  # Tailscale VPN
  services.tailscale.enable = true;

  # networking.firewall.enable = false;
}
