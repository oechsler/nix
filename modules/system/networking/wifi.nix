# WiFi Configuration
#
# WiFi connection profiles (PSK + Enterprise) with SOPS credentials,
# optional ethernet/WiFi autoconnect switching for non-KDE desktops, and iwd profiles.
#
# SSID and identity are declared inline in features.wifi.networks.
# Only the password/psk needs a SOPS secret:
#   WPA2-PSK:        wifi/<name>/psk
#   WPA2 Enterprise: wifi/<name>/password

{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.features.wifi;
  ip6Privacy = if config.features.ipv6PrivacyExtensions.enable then 2 else 0;

  # WPA2-PSK profiles — SSID comes directly from config, PSK from sops placeholder
  wifiProfiles = lib.listToAttrs (
    map (net: {
      name = "wifi-${net.name}";
      value = {
        connection = {
          id = net.ssid;
          type = "wifi";
          autoconnect = true;
        };
        wifi = {
          mode = "infrastructure";
          ssid = net.ssid;
        };
        wifi-security = {
          auth-alg = "open";
          key-mgmt = "wpa-psk";
          psk = "\${WIFI_${lib.toUpper net.name}_PSK}";
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

  # WPA2 Enterprise profiles — SSID and identity come from config, password from sops
  enterpriseWifiProfiles = lib.listToAttrs (
    map (net: {
      name = "wifi-${net.name}";
      value = {
        connection = {
          id = net.ssid;
          type = "wifi";
          autoconnect = true;
        };
        wifi = {
          mode = "infrastructure";
          ssid = net.ssid;
        };
        wifi-security = {
          key-mgmt = "wpa-eap";
        };
        "802-1x" = {
          eap = "peap";
          identity = net.identity;
          password = "\${WIFI_${lib.toUpper net.name}_PASSWORD}";
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

  # Environment file for NetworkManager ensureProfiles — only secrets as vars
  wifiEnvContent =
    lib.concatMapStringsSep "\n" (net:
      "WIFI_${lib.toUpper net.name}_PSK=${config.sops.placeholder."wifi/${net.name}/psk"}"
    ) cfg.networks
    + lib.optionalString (cfg.enterpriseNetworks != [ ]) "\n"
    + lib.concatMapStringsSep "\n" (net:
      "WIFI_${lib.toUpper net.name}_PASSWORD=${config.sops.placeholder."wifi/${net.name}/password"}"
    ) cfg.enterpriseNetworks;

  # Sops secrets — only psk/password, no ssid
  wifiSecrets =
    lib.listToAttrs (
      map (net: { name = "wifi/${net.name}/psk"; value = { }; }) cfg.networks
    )
    // lib.listToAttrs (
      map (net: { name = "wifi/${net.name}/password"; value = { }; }) cfg.enterpriseNetworks
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

    # Ethernet/WiFi switching for desktops without NetworkManager UI policy.
    (lib.mkIf (
      config.features.desktop.enable
      && config.features.desktop.wm != "kde"
      && cfg.enable
      && cfg.preferEthernet.enable
    ) {
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
            net:
            let
              pskPath = config.sops.secrets."wifi/${net.name}/psk".path;
            in
            ''
              ssid_hex=$(printf '%s' "${net.ssid}" | od -An -tx1 | tr -d ' \n')
              mkdir -p /var/lib/iwd
              rm -f "/var/lib/iwd/${net.ssid}.psk"
              printf '[Security]\nPassphrase=%s\n' "$(cat ${pskPath})" \
                > "/var/lib/iwd/=$ssid_hex.psk"
              chmod 0600 "/var/lib/iwd/=$ssid_hex.psk"
            ''
          ) cfg.networks
          + lib.concatMapStringsSep "\n" (
            net:
            let
              passwordPath = config.sops.secrets."wifi/${net.name}/password".path;
            in
            ''
              ssid_hex=$(printf '%s' "${net.ssid}" | od -An -tx1 | tr -d ' \n')
              mkdir -p /var/lib/iwd
              printf '[Security]\nEAP-Method=PEAP\nEAP-Identity=%s\nEAP-PEAP-Phase2-Method=MSCHAPV2\nEAP-PEAP-Phase2-Password=%s\n' \
                "${net.identity}" "$(cat ${passwordPath})" \
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
