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
          # Keep WiFi behind Ethernet for both IPv4 and IPv6 routes.
          Network.RoutePriorityOffset = 2048;
        };
      };
    };

    services = {
      resolved = {
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
    };

    systemd = {
      network.wait-online.enable = false;
      network.networks."10-ethernet-dhcp" = lib.mkIf isHyprland {
        matchConfig.Type = "ether";
        networkConfig.DHCP = "yes";
        ipv6AcceptRAConfig.RouteMetric = 100;
      };
      services = {
        NetworkManager-wait-online.enable = false;
        resolved.serviceConfig.Environment = [ "SYSTEMD_RESOLVED_FALLBACK_DNS=" ];
      };
    };

    services = {
      networkd-dispatcher =
        lib.mkIf
          (isHyprland && config.features.wifi.enable && config.features.hardware.formFactor != "laptop")
          {
            enable = true;
            extraArgs = [ "--run-startup-triggers" ];
            rules = {
              ethernet-wifi-failover = {
                onState = [
                  "routable"
                  "no-carrier"
                  "off"
                ];
                script = ''
                                # iwd's roaming setting is global, so use the wired link state to
                  # avoid mesh roaming while Ethernet is available.
                  event_iface="''${IFACE:-}"
                  operational_state="''${OperationalState:-''${STATE:-}}"

                                is_wireless() {
                                  [ -d "/sys/class/net/$1/wireless" ]
                                }

                                ethernet_is_up() {
                                  for net in /sys/class/net/*; do
                                    iface="''${net##*/}"
                                    [ "$iface" = "$event_iface" ] && continue
                                          is_wireless "$iface" && continue
                                          [ -r "$net/type" ] && [ "$(cat "$net/type")" = 1 ] || continue
                                          [ -r "$net/carrier" ] && [ "$(cat "$net/carrier")" = 1 ] && return 0
                                        done
                                        return 1
                                }

                        # A manually restored WiFi connection must not bypass the wired
                        # preference. Leave WiFi untouched when no Ethernet is available.
                        if is_wireless "$event_iface"; then
                          ethernet_is_up || exit 0
                          ${pkgs.iwd}/bin/iwctl station "$event_iface" disconnect || true
                          exit 0
                        fi

                  if [ "$operational_state" = "routable" ] || ethernet_is_up; then
                                for wireless in /sys/class/net/*/wireless; do
                                  [ -d "$wireless" ] || continue
                                  iface="''${wireless%/wireless}"
                                  iface="''${iface##*/}"
                                ${pkgs.iwd}/bin/iwctl station "$iface" disconnect || true
                                done
                              else
                                        for wireless in /sys/class/net/*/wireless; do
                                  [ -d "$wireless" ] || continue
                                  iface="''${wireless%/wireless}"
                                  iface="''${iface##*/}"
                                ${lib.concatMapStringsSep "\n" (
                                  net: "${pkgs.iwd}/bin/iwctl station \"$iface\" connect ${lib.escapeShellArg net.ssid} || true"
                                ) (config.features.wifi.networks ++ config.features.wifi.enterpriseNetworks)}
                                        done
                                      fi
                '';
              };
            };
          };

      avahi = {
        enable = true;
        nssmdns4 = true;
        openFirewall = true;
        publish = {
          enable = true;
          addresses = true;
        };
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
