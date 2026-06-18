# Base Networking Configuration
#
# NetworkManager, DNS (systemd-resolved), mDNS (Avahi), Ethernet profile,
# and feature toggles for WiFi / Tailscale / IPv6 privacy extensions.
#
# Options:
#   features.ipv6PrivacyExtensions.enable = true;  # IPv6 temporary addresses (default: !server)
#   features.wifi.enable = true;                    # Enable WiFi (default: true)
#   features.wifi.networks = [ "home" ];            # WPA2-PSK networks
#   features.wifi.enterpriseNetworks = [ "uni" ];   # WPA2 Enterprise networks
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
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "WPA2-PSK network names — each needs wifi/<name>/ssid and wifi/<name>/psk SOPS secrets";
      };
      enterpriseNetworks = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "WPA2 Enterprise (EAP-PEAP/MSCHAPv2) network names";
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
           FallbackDNS = ""; # Disable all fallback DNS servers
           DNS = ""; # Clear any static DNS to ensure NetworkManager DNS is used
         };
       };

       # Disable systemd-resolved's built-in fallback DNS servers
       systemd.services.resolved.serviceConfig.Environment = [ "SYSTEMD_RESOLVED_FALLBACK_DNS=" ];

     # Ensure NetworkManager properly hands off DNS to systemd-resolved
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

      # NetworkManager dispatcher to refresh DNS on resume from suspend
      networking.networkmanager.dispatcherScripts = [
        {
          source = pkgs.writeShellScript "99-resolved-refresh" ''
            #!${pkgs.bash}/bin/bash
            if [ "$2" = "resume" ] || [ "$2" = "connectivity-change" ]; then
              ${pkgs.systemd}/bin/resolvectl flush-caches
              # Restart systemd-resolved to pick up new DNS from NetworkManager
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
