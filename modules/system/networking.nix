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
    # 2. Dual-Interface Setup (Hyprland only)
    #---------------------------
    # KDE Plasma handles network priority via plasma-nm, so we only configure this for Hyprland
    (lib.mkIf (config.features.desktop.enable && config.features.desktop.wm == "hyprland") {

      # Ethernet connection profile
      # This ensures Ethernet gets metric 100 (higher priority than WiFi's 600)
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

      #---------------------------
      # Policy-Based Routing Service
      #---------------------------
      # Why: When Ethernet and WiFi are in the same subnet (e.g., both in 172.22.0.0/24),
      # route metrics alone don't ensure packets use the correct interface.
      #
      # Problem: Packets might be sent with WiFi's source IP via Ethernet interface,
      # causing the router to drop them (anti-spoofing / asymmetric routing).
      #
      # Solution: Create separate routing tables for each interface, then use policy rules
      # to ensure packets from each source IP use the correct interface.
      #
      # How it works:
      # - Main routing table: Uses metrics to prefer Ethernet (normal behavior)
      # - Table 100: Ethernet-only routes (172.22.0.163 → Ethernet gateway)
      # - Table 200: WiFi-only routes (172.22.0.167 → WiFi gateway)
      # - Policy rules: "Packets FROM 172.22.0.163 use table 100"
      #                 "Packets FROM 172.22.0.167 use table 200"
      #
      # Result: Each source IP always uses its own interface → no asymmetric routing
      #
      # Note: Safe to run with only Ethernet, only WiFi, or neither.
      #       Gracefully skips missing/unconfigured interfaces.

      systemd.services.policy-routing = {
        description = "Setup policy-based routing for dual network interfaces";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "setup-policy-routing" ''
            set -e

            # Give NetworkManager time to configure interfaces
            ${pkgs.coreutils}/bin/sleep 3

            # Function: Setup policy routing for one interface
            #
            # Args:
            #   $1 = interface name (e.g., "enp5s0")
            #   $2 = routing table number (100 for Ethernet, 200 for WiFi)
            #
            # Steps:
            #   1. Extract IP, gateway, and subnet from interface
            #   2. Add subnet route to table (for local network access)
            #   3. Add default route to table (for internet access)
            #   4. Add policy rule: "packets FROM this IP → use this table"
            setup_interface() {
              local iface=$1
              local table=$2

              # Skip if interface doesn't exist
              if ! ${pkgs.iproute2}/bin/ip link show "$iface" &>/dev/null; then
                echo "Interface $iface not found, skipping"
                return
              fi

              # Extract network configuration from interface
              # - ip: The interface's IP address (e.g., "172.22.0.163")
              # - gateway: The router's IP (e.g., "172.22.0.1")
              # - subnet: The network subnet (e.g., "172.22.0.0/24")
              local ip=$(${pkgs.iproute2}/bin/ip -4 addr show "$iface" 2>/dev/null \
                | ${pkgs.gnugrep}/bin/grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)

              local gateway=$(${pkgs.iproute2}/bin/ip -4 route show dev "$iface" 2>/dev/null \
                | ${pkgs.gnugrep}/bin/grep -oP '(?<=via\s)\d+(\.\d+){3}' | head -1)

              # Get subnet from existing kernel route (must be network address, not host)
              # Example: "172.22.0.0/24" (correct) vs "172.22.0.163/24" (wrong)
              local subnet=$(${pkgs.iproute2}/bin/ip -4 route show dev "$iface" proto kernel scope link 2>/dev/null \
                | ${pkgs.gnugrep}/bin/grep -oP '^\d+(\.\d+){3}/\d+' | head -1)

              # Skip if interface has no IP or gateway (not configured yet)
              if [ -z "$ip" ] || [ -z "$gateway" ]; then
                echo "No IP or gateway for $iface, skipping"
                return
              fi

              echo "Setting up policy routing for $iface"
              echo "  IP: $ip, Gateway: $gateway, Subnet: $subnet, Table: $table"

              # Clean up: Remove any existing policy rules for this IP
              # (Prevents duplicates when service restarts)
              while ${pkgs.iproute2}/bin/ip rule del from "$ip" 2>/dev/null; do :; done

              # Step 1: Add subnet route to routing table
              # This allows accessing other devices in the local network (e.g., 172.22.0.1-254)
              if ${pkgs.iproute2}/bin/ip route add "$subnet" dev "$iface" scope link table $table 2>&1; then
                echo "  ✓ Added subnet route: $subnet dev $iface table $table"
              else
                echo "  ⚠ Subnet route already exists (harmless)"
              fi

              # Step 2: Add default route to routing table
              # This routes all internet traffic via this interface's gateway
              if ${pkgs.iproute2}/bin/ip route add default via "$gateway" dev "$iface" table $table 2>&1; then
                echo "  ✓ Added default route: default via $gateway dev $iface table $table"
              else
                echo "  ⚠ Default route already exists (harmless)"
              fi

              # Step 3: Add policy rule
              # "Packets FROM this IP must use this routing table"
              # This is the key: ensures source IP and interface always match
              ${pkgs.iproute2}/bin/ip rule add from "$ip" table $table priority 100
              echo "  ✓ Added policy rule: from $ip lookup table $table"

              echo "✓ Policy routing complete for $iface"
            }

            # Setup Ethernet (table 100)
            # Try common Ethernet interface names
            for iface in enp5s0 eth0 en*; do
              if ${pkgs.iproute2}/bin/ip link show "$iface" &>/dev/null; then
                setup_interface "$iface" 100
                break
              fi
            done

            # Setup WiFi (table 200)
            # Try common WiFi interface names
            for iface in wlan0 wlp*; do
              if ${pkgs.iproute2}/bin/ip link show "$iface" &>/dev/null; then
                setup_interface "$iface" 200
                break
              fi
            done

            echo "✓ Policy-based routing setup complete"
          '';
        };
      };
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
