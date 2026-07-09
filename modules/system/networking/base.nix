# Base Networking Configuration
#
# NetworkManager, DNS (systemd-resolved), mDNS (Avahi), Ethernet profile,
# and feature toggles for WiFi / Tailscale / IPv6 privacy extensions.
#
# Options:
#   features.ipv6PrivacyExtensions.enable = true;  # IPv6 temporary addresses (default: !server)
#   features.wifi.enable = true;                    # Enable WiFi (default: true)
#   features.wifi.networks = [                      # WPA2-PSK networks
#     { name = "home"; ssid = "MyNetwork"; }        #   psk in sops: wifi/<name>/psk
#   ];
#   features.wifi.enterpriseNetworks = [            # WPA2 Enterprise (EAP-PEAP) networks
#     { name = "uni"; ssid = "Eduroam"; identity = "user@uni.de"; } # password in sops: wifi/<name>/password
#   ];
#   features.wifi.preferEthernet.enable = true;     # Disable WiFi when Ethernet is active (default: true, non-KDE desktops)
#   features.tailscale.enable = true;               # Tailscale VPN (default: true)

{
  config,
  pkgs,
  lib,
  ...
}:

let
  ip6Privacy = if config.features.ipv6PrivacyExtensions.enable then 2 else 0;
in
{
  options.features = {
    ipv6PrivacyExtensions.enable =
      (lib.mkEnableOption "IPv6 privacy extensions for NetworkManager profiles")
      // {
        default = !config.features.server;
      };
    wifi = {
      enable = (lib.mkEnableOption "WiFi with managed network profiles") // {
        default = true;
      };
      networks = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Internal identifier — used as sops key (wifi/<name>/psk).";
            };
            ssid = lib.mkOption {
              type = lib.types.str;
              description = "WiFi network SSID (broadcast name).";
            };
          };
        });
        default = [ ];
        description = "WPA2-PSK networks. Only wifi/<name>/psk needs a SOPS secret.";
      };
      enterpriseNetworks = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Internal identifier — used as sops key (wifi/<name>/password).";
            };
            ssid = lib.mkOption {
              type = lib.types.str;
              description = "WiFi network SSID (broadcast name).";
            };
            identity = lib.mkOption {
              type = lib.types.str;
              description = "EAP identity (e.g. user@university.edu).";
            };
          };
        });
        default = [ ];
        description = "WPA2 Enterprise (EAP-PEAP/MSCHAPv2) networks. Only wifi/<name>/password needs a SOPS secret.";
      };
      preferEthernet.enable = (lib.mkEnableOption "disable WiFi while Ethernet is connected on non-KDE desktops") // {
        default = true;
      };
    };
    tailscale.enable = (lib.mkEnableOption "Tailscale VPN") // {
      default = true;
    };
  };

   config = {
     networking = {
       networkmanager = {
         enable = true;
         wifi.backend = "iwd";
         unmanaged = [
           "interface-name:docker*"
           "interface-name:br-*"
           "interface-name:veth*"
           "interface-name:tailscale*"
         ];
         ensureProfiles.profiles.ethernet-default = {
           connection = {
             id = "Ethernet";
             type = "ethernet";
             autoconnect = true;
             autoconnect-priority = 999;
           };
           ipv4 = {
             method = "auto";
             route-metric = 100;
             dns-priority = 100;
             ignore-auto-dns = false;
           };
           ipv6 = {
             method = "auto";
             ip6-privacy = ip6Privacy;
             route-metric = 100;
             dns-priority = 100;
             ignore-auto-dns = false;
           };
         };
       };
       wireless.iwd = {
         enable = true;
         settings.General.EnableNetworkConfiguration = false;
       };
     };

     services.resolved = {
       enable = true;
       settings.Resolve = {
         DNSSEC = "allow-downgrade";
         Domains = [ "~." ];
         LLMNR = false;
         MulticastDNS = false;
         Cache = true;
         DNSStubListener = true;
         FallbackDNS = "";
         DNS = "";
       };
     };

     systemd.services.resolved.serviceConfig.Environment = [ "SYSTEMD_RESOLVED_FALLBACK_DNS=" ];

     networking.networkmanager.settings = {
       main = {
         dns = "systemd-resolved";
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

     networking.networkmanager.dispatcherScripts = [
       {
         source = pkgs.writeShellScript "99-resolved-refresh" ''
           #!${pkgs.bash}/bin/bash
           if [ "$2" = "resume" ] || [ "$2" = "connectivity-change" ]; then
             ${pkgs.systemd}/bin/resolvectl flush-caches
             ${pkgs.systemd}/bin/systemctl restart systemd-resolved.service
           fi
         '';
         type = "basic";
       }
     ];

     environment.systemPackages = with pkgs; [
       avahi
       iwd
     ];
   };
}
