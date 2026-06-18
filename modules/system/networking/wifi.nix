# WiFi Configuration
#
# WiFi connection profiles (PSK + Enterprise) with SOPS credentials,
# ethernet/WiFi autoconnect switching for desktops, and iwd profiles.
#
# WiFi credentials are stored in SOPS secrets:
#   WPA2-PSK:        wifi/<name>/ssid, wifi/<name>/psk
#   WPA2 Enterprise: wifi/<name>/ssid, wifi/<name>/identity, wifi/<name>/password
#                    (EAP-PEAP with MSCHAPv2 inner auth)

{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.features.wifi;
  ip6Privacy = if config.features.ipv6PrivacyExtensions.enable then 2 else 0;

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
           route-metric = 600;
           dns-priority = 50;
           ignore-auto-dns = false;
         };
         ipv6 = {
           method = "auto";
           ip6-privacy = ip6Privacy;
           route-metric = 600;
           dns-priority = 50;
           ignore-auto-dns = false;
         };
       };
    }) cfg.networks
  );

  wifiEnvContent =
    lib.concatMapStringsSep "\n" (name: ''
      WIFI_${lib.toUpper name}_SSID=${config.sops.placeholder."wifi/${name}/ssid"}
      WIFI_${lib.toUpper name}_PSK=${config.sops.placeholder."wifi/${name}/psk"}'') cfg.networks
    + lib.optionalString (cfg.enterpriseNetworks != [ ]) "\n"
    + lib.concatMapStringsSep "\n" (name: ''
      WIFI_${lib.toUpper name}_SSID=${config.sops.placeholder."wifi/${name}/ssid"}
      WIFI_${lib.toUpper name}_IDENTITY=${config.sops.placeholder."wifi/${name}/identity"}
      WIFI_${lib.toUpper name}_PASSWORD=${
        config.sops.placeholder."wifi/${name}/password"
      }'') cfg.enterpriseNetworks;

  enterpriseWifiProfiles = lib.listToAttrs (
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
          key-mgmt = "wpa-eap";
        };
         "802-1x" = {
           eap = "peap;";
           identity = "\${WIFI_${lib.toUpper name}_IDENTITY}";
           password = "\${WIFI_${lib.toUpper name}_PASSWORD}";
           phase2-auth = "mschapv2";
         };
         ipv4 = {
           method = "auto";
           route-metric = 600;
           dns-priority = 50;
           ignore-auto-dns = false;
         };
         ipv6 = {
           method = "auto";
           ip6-privacy = ip6Privacy;
           route-metric = 600;
           dns-priority = 50;
           ignore-auto-dns = false;
         };
      };
    }) cfg.enterpriseNetworks
  );

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
      ++ map (name: [
        {
          name = "wifi/${name}/ssid";
          value = { };
        }
        {
          name = "wifi/${name}/identity";
          value = { };
        }
        {
          name = "wifi/${name}/password";
          value = { };
        }
      ]) cfg.enterpriseNetworks
    )
  );

  ethernetWifiSwitch = pkgs.writeShellScript "ethernet-wifi-switch" ''
    INTERFACE=''${1:-}
    ACTION=''${2:-up}

    if [ -z "$INTERFACE" ] && [ $# -gt 0 ]; then
      exit 0
    fi

    case "$ACTION" in
      up|down|connectivity-change|dhcp4-change|dhcp6-change) ;;
      *) exit 0 ;;
    esac

    if [ -n "$INTERFACE" ] && [ ! -d "/sys/class/net/$INTERFACE/device" ]; then
      exit 0
    fi

    WIFI_CONNECTIONS=$(${pkgs.networkmanager}/bin/nmcli -t -f NAME,TYPE connection show | ${pkgs.gnugrep}/bin/grep ':802-11-wireless$' | ${pkgs.coreutils}/bin/cut -d: -f1)

    if [ -z "$WIFI_CONNECTIONS" ]; then
      exit 0
    fi

    ACTIVE_ETHERNET=$(${pkgs.networkmanager}/bin/nmcli -t -f TYPE,DEVICE connection show --active | ${pkgs.gnugrep}/bin/grep '^802-3-ethernet:' | ${pkgs.coreutils}/bin/cut -d: -f2 || true)

    if [ -n "$ACTIVE_ETHERNET" ]; then
      ${pkgs.util-linux}/bin/logger "NetworkManager dispatcher: active Ethernet found ($ACTIVE_ETHERNET), disabling WiFi autoconnect"

      while IFS= read -r conn; do
        ${pkgs.networkmanager}/bin/nmcli connection modify "$conn" connection.autoconnect no || true
        ${pkgs.networkmanager}/bin/nmcli connection down "$conn" || true
      done <<< "$WIFI_CONNECTIONS"

      exit 0
    fi

    ${pkgs.util-linux}/bin/logger "NetworkManager dispatcher: no active Ethernet found, enabling WiFi autoconnect"

    while IFS= read -r conn; do
      ${pkgs.networkmanager}/bin/nmcli connection modify "$conn" connection.autoconnect yes || true
    done <<< "$WIFI_CONNECTIONS"

    WIFI_DEVICE=$(${pkgs.networkmanager}/bin/nmcli -t -f DEVICE,TYPE device status | ${pkgs.gnugrep}/bin/grep ':wifi$' | ${pkgs.coreutils}/bin/cut -d: -f1 | ${pkgs.coreutils}/bin/head -n1)

    if [ -n "$WIFI_DEVICE" ]; then
      ${pkgs.networkmanager}/bin/nmcli radio wifi on || true
      ${pkgs.networkmanager}/bin/nmcli device connect "$WIFI_DEVICE" || true
    fi
  '';
in
{
  config = lib.mkMerge [

    # Ethernet/WiFi switching (desktop only)
    (lib.mkIf (config.features.desktop.enable && cfg.enable) {
      networking.networkmanager.dispatcherScripts = [
        {
          source = ethernetWifiSwitch;
          type = "basic";
        }
      ];

      systemd.services.ethernet-wifi-switch = {
        description = "Apply Ethernet/WiFi autoconnect policy";
        wantedBy = [ "multi-user.target" ];
        after = [ "NetworkManager.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = ethernetWifiSwitch;
        };
      };

      systemd.services.networkmanager-cleanup-ethernet-profiles = {
        description = "Remove unmanaged Ethernet connection profiles";
        wantedBy = [ "multi-user.target" ];
        after = [
          "NetworkManager.service"
          "NetworkManager-ensure-profiles.service"
        ];
        serviceConfig = {
          Type = "oneshot";
        };
        script = ''
          ${pkgs.networkmanager}/bin/nmcli -t -f NAME,TYPE connection show \
            | while IFS=: read -r name type; do
                if [ "$type" = "802-3-ethernet" ] && [ "$name" != "Ethernet" ]; then
                  ${pkgs.util-linux}/bin/logger "NetworkManager cleanup: deleting unmanaged Ethernet profile '$name'"
                  ${pkgs.networkmanager}/bin/nmcli connection delete "$name" || true
                fi
              done
        '';
      };
    })

    # WiFi disabled
    (lib.mkIf (!cfg.enable) {
      networking.networkmanager.wifi.powersave = false;
      networking.networkmanager.unmanaged = [ "type:wifi" ];
    })

    # WiFi profiles + iwd
    (lib.mkIf cfg.enable {
      networking.networkmanager.ensureProfiles = {
        environmentFiles = [ config.sops.templates."wifi-env".path ];
        profiles = wifiProfiles // enterpriseWifiProfiles;
      };

      systemd.services.NetworkManager-ensure-profiles = {
        after = [ "sops-install-secrets.service" ];
        unitConfig.ConditionPathExists = config.sops.age.keyFile;
      };

      systemd.services.iwd-profiles = {
        wantedBy = [ "network-pre.target" ];
        after = [ "sops-install-secrets.service" ];
        before = [ "iwd.service" ];
        unitConfig.ConditionPathExists = config.sops.age.keyFile;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script =
          lib.concatMapStringsSep "\n" (
            name:
            let
              ssidPath = config.sops.secrets."wifi/${name}/ssid".path;
              pskPath = config.sops.secrets."wifi/${name}/psk".path;
            in
            ''
              ssid=$(cat ${ssidPath})
              ssid_hex=$(printf '%s' "$ssid" | od -An -tx1 | tr -d ' \n')
              mkdir -p /var/lib/iwd
              rm -f "/var/lib/iwd/$ssid.psk"
              printf '[Security]\nPassphrase=%s\n' "$(cat ${pskPath})" \
                > "/var/lib/iwd/=$ssid_hex.psk"
              chmod 0600 "/var/lib/iwd/=$ssid_hex.psk"
            ''
          ) cfg.networks
          + lib.concatMapStringsSep "\n" (
            name:
            let
              ssidPath = config.sops.secrets."wifi/${name}/ssid".path;
              identityPath = config.sops.secrets."wifi/${name}/identity".path;
              passwordPath = config.sops.secrets."wifi/${name}/password".path;
            in
            ''
              ssid=$(cat ${ssidPath})
              ssid_hex=$(printf '%s' "$ssid" | od -An -tx1 | tr -d ' \n')
              mkdir -p /var/lib/iwd
              printf '[Security]\nEAP-Method=PEAP\nEAP-Identity=%s\nEAP-PEAP-Phase2-Method=MSCHAPV2\nEAP-PEAP-Phase2-Password=%s\n' \
                "$(cat ${identityPath})" "$(cat ${passwordPath})" \
                > "/var/lib/iwd/=$ssid_hex.8021x"
              chmod 0600 "/var/lib/iwd/=$ssid_hex.8021x"
            ''
          ) cfg.enterpriseNetworks;
      };

      sops = {
        templates."wifi-env".content = wifiEnvContent;
        secrets = wifiSecrets;
      };
    })
  ];
}
