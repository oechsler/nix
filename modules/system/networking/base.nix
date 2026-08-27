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
#   features.tailscale.enable = true;               # Tailscale VPN (default: true)

{
  config,
  pkgs,
  lib,
  ...
}:

let
  ip6Privacy = if config.features.ipv6PrivacyExtensions.enable then 2 else 0;
  isHyprland = config.features.desktop.enable && config.features.desktop.wm == "hyprland";
in
{
  options.features = {
    ipv6PrivacyExtensions.enable =
      (lib.mkEnableOption "IPv6 privacy extensions for NetworkManager profiles")
      // {
        default = true;
      };
    wifi = {
      enable = (lib.mkEnableOption "WiFi with managed network profiles") // {
        default = true;
      };
      networks = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
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
          }
        );
        default = [ ];
        description = "WPA2-PSK networks. Only wifi/<name>/psk needs a SOPS secret.";
      };
      enterpriseNetworks = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
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
          }
        );
        default = [ ];
        description = "WPA2 Enterprise (EAP-PEAP/MSCHAPv2) networks. Only wifi/<name>/password needs a SOPS secret.";
      };
    };
    tailscale.enable = (lib.mkEnableOption "Tailscale VPN") // {
      default = true;
    };
  };

  config = {
    # Network availability must not block boot. Network services can start
    # and retry in the background after the desktop is available.
    networking = {
      useDHCP = false;
      useNetworkd = isHyprland;
      networkmanager = {
        enable = !isHyprland;
        wifi.backend = "iwd";
        settings = lib.mkIf (!isHyprland) {
          main.dns = "systemd-resolved";
        };
        unmanaged = [
          "interface-name:docker*"
          "interface-name:br-*"
          "interface-name:veth*"
          "interface-name:tailscale*"
        ]
        ++ lib.optional isHyprland "type:wifi";
        ensureProfiles.profiles.ethernet-default = lib.mkIf (!isHyprland) {
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
        settings = {
          General.EnableNetworkConfiguration = isHyprland;
          # systemd-networkd's DHCP default route metric is 1024; Ethernet
          # must remain preferred while iwd still provides a WiFi fallback.
          Network.RoutePriorityOffset = 2048;
        };
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

    systemd = {
      network.wait-online.enable = false;
      network.networks."10-ethernet-dhcp" = lib.mkIf isHyprland {
        matchConfig.Type = "ether";
        networkConfig.DHCP = "yes";
      };
      services = {
        NetworkManager-wait-online.enable = false;
        resolved.serviceConfig.Environment = [ "SYSTEMD_RESOLVED_FALLBACK_DNS=" ];
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
            # NetworkManager owns the resolver lifecycle. Restarting resolved
            # here races with its link updates during resume and can trigger
            # systemd's start-limit protection.
            ${pkgs.systemd}/bin/resolvectl flush-caches || true
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
