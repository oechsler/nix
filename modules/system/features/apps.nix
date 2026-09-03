# Desktop application feature options.

{ config, lib, ... }:

{
  options.features.apps = {
    enable = (lib.mkEnableOption "desktop applications (Discord, Spotify, etc.)") // {
      default = true;
    };

    mumble = {
      enable = (lib.mkEnableOption "Mumble voice chat") // {
        default = true;
      };
      username = lib.mkOption {
        type = lib.types.str;
        default = config.user.name;
        description = "Default Mumble username.";
      };
      playMuteCue = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Play a sound when Mumble is muted or unmuted.";
      };
      channelExpansionMode = lib.mkOption {
        type = lib.types.str;
        default = "AllChannels";
        description = "Mumble channel expansion mode.";
      };
      disablePublicServerList = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Disable Mumble's public server list.";
      };
      autoConnectToLastServer = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Automatically connect to the last Mumble server.";
      };
      reconnectAutomatically = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Reconnect automatically after a connection loss.";
      };
      hideInTray = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Keep Mumble in the system tray instead of the taskbar.";
      };
      quitBehavior = lib.mkOption {
        type = lib.types.enum [
          "AlwaysAsk"
          "AskWhenConnected"
          "AlwaysMinimize"
          "MinimizeWhenConnected"
          "AlwaysQuit"
        ];
        default = "AlwaysMinimize";
        description = "What Mumble does when its window is closed.";
      };
      serverFilterMode = lib.mkOption {
        type = lib.types.enum [
          "ShowPopulated"
          "ShowReachable"
          "ShowAll"
        ];
        default = "ShowAll";
        description = "Which servers are shown in the Mumble server list.";
      };
      servers = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              name = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Optional display name; defaults to the server hostname.";
              };
              host = lib.mkOption {
                type = lib.types.str;
                description = "Mumble server hostname.";
              };
              port = lib.mkOption {
                type = lib.types.port;
                default = 64738;
              };
              username = lib.mkOption {
                type = lib.types.str;
                default = config.features.apps.mumble.username;
              };
            };
          }
        );
        default = [ ];
        description = "Mumble servers shown in the server list.";
      };
    };
    nextcloud = {
      enable = (lib.mkEnableOption "Nextcloud client") // {
        default = config.features.apps.enable;
      };
    };
  };
}
