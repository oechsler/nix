# Mumble voice chat configuration
#
# This module installs Mumble, manages its user configuration and provides
# desktop-specific launch commands for KDE and Hyprland.

{
  config,
  lib,
  pkgs,
  features,
  ...
}:

let
  cfg = features.apps.mumble;
  configFile = "$HOME/.config/Mumble/Mumble/mumble_settings.json";
  databaseFile = "$HOME/.local/share/Mumble/Mumble/mumble.sqlite";
  certificatePath =
    if cfg.certificate.enable then config.sops.secrets."mumble/certificate".path else "/dev/null";

  mumbleConfig = pkgs.writeText "mumble-settings.json" (
    builtins.toJSON {
      audio = {
        echo_cancel_mode = "Disabled";
        # PipeWire provides the PulseAudio compatibility server. Mumble's
        # native PipeWire backend currently crashes during audio startup.
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
        hide_in_tray = cfg.hideInTray;
        quit_behavior = cfg.quitBehavior;
        send_usage_statistics = false;
        server_filter_mode = cfg.serverFilterMode;
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

  updateConfig = pkgs.writeShellScript "mumble-config-update" ''
    set -eu

    mumble_config="${configFile}"
    mumble_database="${databaseFile}"

    if [ ! -e "$mumble_config" ]; then
      mkdir -p "$(dirname "$mumble_config")"
      cp ${mumbleConfig} "$mumble_config"
    fi

    if [ -f "$mumble_config" ]; then
      mumble_tmp="$(mktemp "''${mumble_config}.XXXXXX")"
      if ${pkgs.jq}/bin/jq \
        --arg username ${lib.escapeShellArg cfg.username} \
        --argjson public-list ${lib.boolToString (!cfg.disablePublicServerList)} \
        '.audio.input_system = "PulseAudio"
         | .audio.output_system = "PulseAudio"
         | .ui.theme = ""
         | .ui.theme_style = ""
         | .last_connection.username = $username
         | .ui.disable_public_server_list = ($public-list | not)
         | .network.auto_connect_to_last_server = ${lib.boolToString cfg.autoConnectToLastServer}
         | .network.reconnect_automatically = ${lib.boolToString cfg.reconnectAutomatically}
         | .ui.hide_in_tray = ${lib.boolToString cfg.hideInTray}
         | .ui.quit_behavior = "${cfg.quitBehavior}"
         | .ui.server_filter_mode = "${cfg.serverFilterMode}"' \
        "$mumble_config" > "$mumble_tmp"; then
        chmod --reference="$mumble_config" "$mumble_tmp"
        mv "$mumble_tmp" "$mumble_config"
      else
        rm -f "$mumble_tmp"
      fi
    fi

    if ${lib.boolToString cfg.certificate.enable} && [ -r "${certificatePath}" ] && [ -f "$mumble_config" ]; then
      mumble_tmp="$(mktemp "''${mumble_config}.XXXXXX")"
      if ${pkgs.jq}/bin/jq --rawfile certificate "${certificatePath}" \
        '.net.certificate = ($certificate | gsub("\\s"; ""))' \
        "$mumble_config" > "$mumble_tmp"; then
        chmod --reference="$mumble_config" "$mumble_tmp"
        mv "$mumble_tmp" "$mumble_config"
      else
        rm -f "$mumble_tmp"
      fi
    elif ! ${lib.boolToString cfg.certificate.enable} && [ -f "$mumble_config" ]; then
      mumble_tmp="$(mktemp "''${mumble_config}.XXXXXX")"
      if ${pkgs.jq}/bin/jq 'del(.net.certificate)' "$mumble_config" > "$mumble_tmp"; then
        chmod --reference="$mumble_config" "$mumble_tmp"
        mv "$mumble_tmp" "$mumble_config"
      else
        rm -f "$mumble_tmp"
      fi
    fi

    mkdir -p "$(dirname "$mumble_database")"
    ${pkgs.sqlite}/bin/sqlite3 "$mumble_database" \
      'CREATE TABLE IF NOT EXISTS servers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, hostname TEXT, port INTEGER DEFAULT 64738, username TEXT, password TEXT, url TEXT);'
    ${serverSql}
  '';

  setQuitNormallyCommand = pkgs.writeShellScript "mumble-set-quit-flag" ''
    [ -n "''${MAINPID:-}" ] || exit 0
    kill -0 "$MAINPID" 2>/dev/null || exit 0
    [ -f "${configFile}" ] || exit 0
    ${pkgs.jq}/bin/jq '.mumble_has_quit_normally = true' "${configFile}" > "${configFile}.tmp"
    ${pkgs.coreutils}/bin/mv "${configFile}.tmp" "${configFile}"
  '';
in
{
  options.programs.mumble = {
    command = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${pkgs.mumble}/bin/mumble";
      description = "Direct Mumble command for desktop launchers.";
    };

    setQuitNormallyCommand = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${setQuitNormallyCommand}";
      description = "Command used to mark Mumble as cleanly closed.";
    };
  };

  config = lib.mkIf (features.apps.enable && cfg.enable) {
    home.packages = [ pkgs.mumble ];
    sops.secrets."mumble/certificate" = lib.mkIf cfg.certificate.enable { };

    home.activation.mumbleConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${updateConfig}
    '';
  };
}
