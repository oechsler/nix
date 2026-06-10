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

{ config, pkgs, lib, ... }:

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
          };
          ipv6 = {
            method = "auto";
            ip6-privacy = ip6Privacy;
            route-metric = 100;
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

    environment.systemPackages = with pkgs; [
      avahi
      iwd
    ];
  };
}
