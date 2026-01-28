{ config, pkgs, lib, ... }:

{
  networking.networkmanager = {
    enable = true;

    # WiFi Profile mit sops secrets
    ensureProfiles = {
      environmentFiles = [ config.sops.templates."wifi-env".path ];
      profiles = {
        "home-wifi" = {
          connection = {
            id = "\${WIFI_SSID}";
            type = "wifi";
            autoconnect = true;
          };
          wifi = {
            mode = "infrastructure";
            ssid = "\${WIFI_SSID}";
          };
          wifi-security = {
            auth-alg = "open";
            key-mgmt = "wpa-psk";
            psk = "\${WIFI_PSK}";
          };
          ipv4.method = "auto";
          ipv6.method = "auto";
        };
      };
    };
  };

  # Template für Umgebungsvariablen aus sops secrets
  sops.templates."wifi-env" = {
    content = ''
      WIFI_SSID=${config.sops.placeholder.wifi_ssid}
      WIFI_PSK=${config.sops.placeholder.wifi_psk}
    '';
  };

  # networking.firewall.enable = false;
}
