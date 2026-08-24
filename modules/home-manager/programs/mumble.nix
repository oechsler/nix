# Mumble voice chat configuration
#
# This module configures:
# - Mumble installation and declarative user settings
# - Favorite servers and default username
# - Desktop integration for KDE and Hyprland

{
  config,
  lib,
  pkgs,
  features,
  ...
}:

let
  cfg = features.apps.mumble;
  mumbleConfig = pkgs.writeText "mumble-settings.json" (
    builtins.toJSON {
      audio = {
        echo_cancel_mode = "Disabled";
        input_system = "PulseAudio";
        output_system = "PulseAudio";
        play_mute_cue = false;
      };
      misc = {
        audio_wizard_has_been_shown = true;
        viewed_server_ping_consent_message = true;
      };
      network.auto_connect_to_last_server = cfg.autoConnectToLastServer;
      network.reconnect_automatically = cfg.reconnectAutomatically;
      ui = {
        channel_expansion_mode = "AllChannels";
        disable_public_server_list = cfg.disablePublicServerList;
        quit_behavior = cfg.quitBehavior;
        hide_in_tray = cfg.hideInTray;
        server_filter_mode = cfg.serverFilterMode;
        send_usage_statistics = false;
        theme = "";
        theme_style = "";
      };
      last_connection = {
        inherit (cfg) username;
        server_name = lib.optionalString (cfg.servers != [ ]) (serverName (builtins.head cfg.servers));
      };
    }
  );
  serverName = server: if server.name == null then server.host else server.name;
  sqlValue = value: lib.replaceStrings [ "'" ] [ "''" ] value;
  serverSql = lib.concatMapStrings (server: ''
    ${pkgs.sqlite}/bin/sqlite3 "$mumble_database" ${lib.escapeShellArg ''
      DELETE FROM servers WHERE hostname = '${sqlValue server.host}' AND port = ${toString server.port};
      INSERT INTO servers (name, hostname, port, username, password, url)
        VALUES ('${sqlValue (serverName server)}', '${sqlValue server.host}', ${toString server.port},
                '${sqlValue server.username}', NULL, NULL);
    ''}
  '') cfg.servers;
  command = pkgs.writeShellScript "mumble-launcher" ''
    config_file="$HOME/.config/Mumble/Mumble/mumble_settings.json"
    if [ -f "$config_file" ]; then
      ${pkgs.jq}/bin/jq '.mumble_has_quit_normally = true | .ui.theme = "" | .ui.theme_style = "" | .ui.disable_public_server_list = ${lib.boolToString cfg.disablePublicServerList}' \
        "$config_file" > "$config_file.tmp" && ${pkgs.coreutils}/bin/mv "$config_file.tmp" "$config_file"
    fi
    if [ -r "${config.sops.secrets."mumble/certificate".path}" ] && [ -f "$config_file" ]; then
      certificate_tmp="$(${pkgs.coreutils}/bin/mktemp)"
      if ${pkgs.coreutils}/bin/base64 -d "${
        config.sops.secrets."mumble/certificate".path
      }" > "$certificate_tmp" \
        && ${pkgs.jq}/bin/jq --rawfile certificate "$certificate_tmp" '.net.certificate = ($certificate | @base64)' "$config_file" > "$config_file.tmp"; then
        ${pkgs.coreutils}/bin/mv "$config_file.tmp" "$config_file"
      fi
      ${pkgs.coreutils}/bin/rm -f "$certificate_tmp" "$config_file.tmp"
    fi
    exec ${pkgs.mumble}/bin/mumble "$@"
  '';
  setQuitNormallyCommand = pkgs.writeShellScript "mumble-set-quit-flag" ''
    [ -n "''${MAINPID:-}" ] && kill -0 "$MAINPID" 2>/dev/null || exit 0
    config_file="$HOME/.config/Mumble/Mumble/mumble_settings.json"
    [ -f "$config_file" ] || exit 0
    ${pkgs.jq}/bin/jq '.mumble_has_quit_normally = true' "$config_file" > "$config_file.tmp" \
      && ${pkgs.coreutils}/bin/mv "$config_file.tmp" "$config_file"
  '';
in
{
  options.programs.mumble = {
    command = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${command}";
    };
    setQuitNormallyCommand = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${setQuitNormallyCommand}";
    };
  };

  config = lib.mkIf (features.apps.enable && cfg.enable) {
    home.packages = [ pkgs.mumble ];
    sops.secrets."mumble/certificate" = { };
    home.activation.mumbleConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mumble_config="$HOME/.config/Mumble/Mumble/mumble_settings.json"
      if [ ! -e "$mumble_config" ]; then
        mkdir -p "$(dirname "$mumble_config")"
        cp ${mumbleConfig} "$mumble_config"
      fi
      if [ -f "$mumble_config" ]; then
        mumble_tmp="$(mktemp "''${mumble_config}.XXXXXX")"
        if ${pkgs.jq}/bin/jq \
          --arg username ${lib.escapeShellArg cfg.username} \
          --argjson public-list ${lib.boolToString (!cfg.disablePublicServerList)} \
          '.ui.theme = "" | .ui.theme_style = "" | .last_connection.username = $username | .ui.disable_public_server_list = ($public-list | not) | .network.auto_connect_to_last_server = ${lib.boolToString cfg.autoConnectToLastServer} | .network.reconnect_automatically = ${lib.boolToString cfg.reconnectAutomatically} | .ui.hide_in_tray = ${lib.boolToString cfg.hideInTray} | .ui.quit_behavior = "${cfg.quitBehavior}" | .ui.server_filter_mode = "${cfg.serverFilterMode}"' \
          "$mumble_config" > "$mumble_tmp"; then
          chmod --reference="$mumble_config" "$mumble_tmp"
          mv "$mumble_tmp" "$mumble_config"
        else
          rm -f "$mumble_tmp"
        fi
      fi

      if [ -r "${config.sops.secrets."mumble/certificate".path}" ] && [ -f "$mumble_config" ]; then
        mumble_certificate_tmp="$(mktemp)"
        mumble_tmp="$(mktemp "''${mumble_config}.XXXXXX")"
        if base64 -d ${config.sops.secrets."mumble/certificate".path} > "$mumble_certificate_tmp" \
          && ${pkgs.jq}/bin/jq --rawfile certificate "$mumble_certificate_tmp" \
          '.net.certificate = ($certificate | @base64)' "$mumble_config" > "$mumble_tmp"; then
          chmod --reference="$mumble_config" "$mumble_tmp"
          mv "$mumble_tmp" "$mumble_config"
        else
          rm -f "$mumble_tmp"
        fi
        rm -f "$mumble_certificate_tmp"
      fi

      mumble_database="$HOME/.local/share/Mumble/Mumble/mumble.sqlite"
      mkdir -p "$(dirname "$mumble_database")"
      ${pkgs.sqlite}/bin/sqlite3 "$mumble_database" \
        'CREATE TABLE IF NOT EXISTS servers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, hostname TEXT, port INTEGER DEFAULT 64738, username TEXT, password TEXT, url TEXT);'
      ${serverSql}
    '';
  };
}
