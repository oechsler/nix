# Mumble voice chat configuration
#
# This module installs Mumble, manages its user configuration and provides
# desktop integration for KDE and Hyprland.

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
  sopsLines = lib.splitString "\n" (builtins.readFile config.sops.defaultSopsFile);
  hasCertificate =
    builtins.any (line: line == "mumble:") sopsLines
    && builtins.any (line: lib.hasPrefix "    certificate:" line) sopsLines;
  certificatePath =
    if hasCertificate then config.sops.secrets."mumble/certificate".path else "/dev/null";

  mumbleConfig = pkgs.writeText "mumble-settings.json" (
    builtins.toJSON {
      mumble_has_quit_normally = true;
      settings_version = 1;
      audio = {
        echo_cancel_mode = "Disabled";
        # PipeWire provides the PulseAudio compatibility server. Mumble's
        # native PipeWire backend currently crashes during audio startup.
        input_system = "PulseAudio";
        output_system = "PulseAudio";
        play_mute_cue = cfg.playMuteCue;
      };
      misc = {
        audio_wizard_has_been_shown = true;
        viewed_server_ping_consent_message = true;
      };
      network.auto_connect_to_last_server = cfg.autoConnectToLastServer;
      network.reconnect_automatically = cfg.reconnectAutomatically;
      ui = {
        channel_expansion_mode = cfg.channelExpansionMode;
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
  serverNameValue = lib.optionalString (cfg.servers != [ ]) (serverName (builtins.head cfg.servers));
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
        --arg server_name ${lib.escapeShellArg serverNameValue} \
        --arg channel_expansion_mode ${lib.escapeShellArg cfg.channelExpansionMode} \
        --arg quit_behavior ${lib.escapeShellArg cfg.quitBehavior} \
        --arg server_filter_mode ${lib.escapeShellArg cfg.serverFilterMode} \
        --argjson play_mute_cue ${lib.boolToString cfg.playMuteCue} \
        --argjson public_list ${lib.boolToString (!cfg.disablePublicServerList)} \
         '.mumble_has_quit_normally = true
          | .settings_version = 1
          | .audio.input_system = "PulseAudio"
         | .audio.output_system = "PulseAudio"
         | .audio.echo_cancel_mode = "Disabled"
         | .audio.play_mute_cue = $play_mute_cue
         | .misc.audio_wizard_has_been_shown = true
         | .misc.viewed_server_ping_consent_message = true
         | .ui.theme = ""
         | .ui.theme_style = ""
         | .ui.channel_expansion_mode = $channel_expansion_mode
         | .last_connection.username = $username
         | .last_connection.server_name = $server_name
         | .ui.disable_public_server_list = ($public_list | not)
         | .network.auto_connect_to_last_server = ${lib.boolToString cfg.autoConnectToLastServer}
         | .network.reconnect_automatically = ${lib.boolToString cfg.reconnectAutomatically}
         | .ui.hide_in_tray = ${lib.boolToString cfg.hideInTray}
         | .ui.quit_behavior = $quit_behavior
         | .ui.send_usage_statistics = false
         | .ui.server_filter_mode = $server_filter_mode' \
        "$mumble_config" > "$mumble_tmp"; then
        chmod --reference="$mumble_config" "$mumble_tmp"
        mv "$mumble_tmp" "$mumble_config"
      else
        rm -f "$mumble_tmp"
      fi
    fi

    if ${lib.boolToString hasCertificate} && [ -r "${certificatePath}" ] && [ -f "$mumble_config" ]; then
      mumble_tmp="$(mktemp "''${mumble_config}.XXXXXX")"
      if ${pkgs.jq}/bin/jq --rawfile certificate "${certificatePath}" \
        '.certificate = ($certificate | gsub("\\s"; ""))' \
        "$mumble_config" > "$mumble_tmp"; then
        chmod --reference="$mumble_config" "$mumble_tmp"
        mv "$mumble_tmp" "$mumble_config"
      else
        rm -f "$mumble_tmp"
      fi
    elif ! ${lib.boolToString hasCertificate} && [ -f "$mumble_config" ]; then
      mumble_tmp="$(mktemp "''${mumble_config}.XXXXXX")"
      if ${pkgs.jq}/bin/jq 'del(.certificate)' "$mumble_config" > "$mumble_tmp"; then
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

    updateConfig = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${updateConfig}";
      description = "Command used to create and update Mumble's configuration.";
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
    sops.secrets."mumble/certificate" = lib.mkIf hasCertificate { };

    # SOPS must refresh the secret file before importing the certificate.
    home.activation.mumbleConfig = lib.hm.dag.entryAfter [ "sops-nix" ] ''
      ${updateConfig}
    '';
  };
}
