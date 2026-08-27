# WiFi Configuration
#
# WiFi connection profiles (PSK + Enterprise) with SOPS credentials.
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
  nmManagedWifi = !(config.features.desktop.enable && config.features.desktop.wm == "hyprland");
  ip6Privacy = if config.features.ipv6PrivacyExtensions.enable then 2 else 0;
  stableUuid =
    profileName:
    let
      hash = builtins.hashString "sha256" "nixos-networkmanager-${profileName}";
    in
    "${lib.substring 0 8 hash}-${lib.substring 8 4 hash}-${lib.substring 12 4 hash}-${lib.substring 16 4 hash}-${lib.substring 20 12 hash}";

  # WPA2-PSK profiles — SSID comes directly from config, PSK from sops placeholder
  wifiProfiles = lib.listToAttrs (
    map (net: {
      name = "wifi-${net.name}";
      value = {
        connection = {
          id = net.ssid;
          type = "wifi";
          uuid = stableUuid "wifi-${net.name}";
          autoconnect = true;
        };
        wifi = {
          mode = "infrastructure";
          inherit (net) ssid;
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
          uuid = stableUuid "wifi-${net.name}";
          autoconnect = true;
        };
        wifi = {
          mode = "infrastructure";
          inherit (net) ssid;
        };
        wifi-security = {
          key-mgmt = "wpa-eap";
        };
        "802-1x" = {
          eap = "peap";
          inherit (net) identity;
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

  managedWifiNetworks = cfg.networks ++ cfg.enterpriseNetworks;
  managedWifiCases = lib.concatMapStringsSep "\n" (
    net: "${lib.escapeShellArg net.ssid})"
  ) managedWifiNetworks;
  managedWifiUuids = lib.concatMapStringsSep "|" (
    net: stableUuid "wifi-${net.name}"
  ) managedWifiNetworks;

  # Environment file for NetworkManager ensureProfiles — only secrets as vars
  wifiEnvContent =
    lib.concatMapStringsSep "\n" (
      net: "WIFI_${lib.toUpper net.name}_PSK=${config.sops.placeholder."wifi/${net.name}/psk"}"
    ) cfg.networks
    + lib.optionalString (cfg.enterpriseNetworks != [ ]) "\n"
    + lib.concatMapStringsSep "\n" (
      net: "WIFI_${lib.toUpper net.name}_PASSWORD=${config.sops.placeholder."wifi/${net.name}/password"}"
    ) cfg.enterpriseNetworks;

  # Sops secrets — only psk/password, no ssid
  wifiSecrets =
    lib.listToAttrs (
      map (net: {
        name = "wifi/${net.name}/psk";
        value = { };
      }) cfg.networks
    )
    // lib.listToAttrs (
      map (net: {
        name = "wifi/${net.name}/password";
        value = { };
      }) cfg.enterpriseNetworks
    );

in
{
  config = lib.mkMerge [
    # WiFi disabled
    (lib.mkIf (!cfg.enable) {
      networking.networkmanager.wifi.powersave = false;
      networking.networkmanager.unmanaged = [ "type:wifi" ];
    })

    # WiFi profiles + iwd
    (lib.mkIf cfg.enable {
      networking.networkmanager.ensureProfiles = lib.mkIf nmManagedWifi {
        environmentFiles = [ config.sops.templates."wifi-env".path ];
        profiles = wifiProfiles // enterpriseWifiProfiles;
      };

      # Remove stale duplicate profiles for declaratively managed SSIDs.
      systemd.services = {
        NetworkManager-reconcile-wifi-profiles = lib.mkIf nmManagedWifi {
          description = "Reconcile declarative NetworkManager WiFi profiles";
          wantedBy = [ "multi-user.target" ];
          wants = [ "NetworkManager-ensure-profiles.service" ];
          after = [
            "NetworkManager.service"
            "NetworkManager-ensure-profiles.service"
          ];
          serviceConfig.Type = "oneshot";
          script = ''
            set -u
            while IFS= read -r uuid; do
              [ -n "$uuid" ] || continue
              id=$(${pkgs.networkmanager}/bin/nmcli -g NAME connection show uuid "$uuid" 2>/dev/null || true)
              type=$(${pkgs.networkmanager}/bin/nmcli -g TYPE connection show uuid "$uuid" 2>/dev/null || true)
              [ "$type" = "802-11-wireless" ] || continue
              case "$id" in
                ${managedWifiCases}
                  case "$uuid" in
                    ${managedWifiUuids}) ;;
                    *) ${pkgs.networkmanager}/bin/nmcli connection delete uuid "$uuid" || true ;;
                  esac
                  ;;
              esac
            done < <(${pkgs.networkmanager}/bin/nmcli -g UUID connection show)
          '';
        };

        NetworkManager-ensure-profiles = lib.mkIf nmManagedWifi {
          after = [ "sops-install-secrets.service" ];
          unitConfig.ConditionPathExists = config.sops.age.keyFile;
        };

        iwd-profiles = lib.mkIf (!nmManagedWifi) {
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
      };

      sops = {
        templates."wifi-env".content = wifiEnvContent;
        secrets = wifiSecrets;
      };
    })
  ];
}
