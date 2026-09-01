# Hyprland monitor profiles
#
# The Nix monitor declaration is exported as a hyprmoncfg profile. Runtime
# layout changes, hotplug handling, and laptop clamshell behavior are owned by
# hyprmoncfgd instead of a second monitor writer.

{
  config,
  pkgs,
  lib,
  displays,
  ...
}:

let
  displayHelpers = import ../../../lib/displays.nix { inherit lib; };
  vrrMode = lib.foldl' (
    mode: monitor: lib.max mode monitor.vrr
  ) displays.defaults.vrr displays.monitors;
  hasHDR = displayHelpers.hasDesktopHDR displays.monitors || displays.defaults.hdr == 2;

  profileOutput = m: {
    key =
      if m.make != null && m.model != null && m.serial != null then
        "${lib.toLower m.make}|${lib.toLower m.model}|${lib.toLower m.serial}"
      else
        m.name;
    match_key = lib.concatStringsSep "|" (
      lib.filter (value: value != null) [
        (if m.make == null then null else lib.toLower m.make)
        (if m.model == null then null else lib.toLower m.model)
        (if m.serial == null then null else lib.toLower m.serial)
      ]
    );
    inherit (m)
      name
      width
      height
      x
      y
      scale
      vrr
      ;
    make = if m.make == null then "" else m.make;
    model = if m.model == null then "" else m.model;
    serial = if m.serial == null then "" else m.serial;
    enabled = true;
    mode = "${toString m.width}x${toString m.height}@${toString m.refreshRate}";
    refresh = m.refreshRate;
    transform =
      {
        normal = 0;
        "90" = 1;
        "180" = 2;
        "270" = 3;
      }
      .${m.rotation};
    bitdepth = if m.hdr == 2 then 10 else 0;
    cm = if m.hdr == 2 then "hdredid" else "";
    sdr_max_luminance = if m.hdr == 2 then m.hdrSdrMaxLuminance else 0;
  };
  profileKey = m: (profileOutput m).key;
  workspacesPerMonitor = displays.defaultWorkspaceCount;
  profileWorkspaceRules = lib.flatten (
    lib.imap0 (
      monitorIndex: m:
      map (workspaceOffset: {
        workspace = toString (monitorIndex * workspacesPerMonitor + workspaceOffset);
        output_key = profileKey m;
        output_name = m.name;
        default = workspaceOffset == 1;
        persistent = true;
      }) (lib.range 1 workspacesPerMonitor)
    ) displays.monitors
  );
  profileJson = builtins.toJSON {
    name = "default";
    created_at = "1970-01-01T00:00:00Z";
    updated_at = "1970-01-01T00:00:00Z";
    outputs = map profileOutput displays.monitors;
    workspaces = {
      enabled = profileWorkspaceRules != [ ];
      strategy = "sequential";
      max_workspaces = workspacesPerMonitor * (builtins.length displays.monitors);
      group_size = workspacesPerMonitor;
      monitor_order = map profileKey displays.monitors;
      rules = profileWorkspaceRules;
    };
    exec = "";
  };
  profileSource = pkgs.writeText "hyprmoncfg-default.json" profileJson;
in
{
  config = {
    systemd.user.services = lib.optionalAttrs (displays.monitors != [ ]) {
      hyprmoncfgd = {
        Unit = {
          Description = "Hyprland monitor profile daemon";
          After = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${pkgs.hyprmoncfg}/bin/hyprmoncfgd";
          Environment = [
            "HYPRLAND_CONFIG=${config.xdg.configHome}/hypr/hyprland.lua"
            "HYPRMONCFG_MONITORS_CONF=${config.xdg.configHome}/hypr/monitors.lua"
          ];
          Restart = "on-failure";
          RestartSec = 3;
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    };

    home.packages = [ pkgs.hyprmoncfg ];

    home.activation.ensureHyprmoncfgDefaultProfile = lib.mkIf (displays.monitors != [ ]) (
      lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
        default_profile="${config.xdg.configHome}/hyprmoncfg/profiles/default.json"
        if [ -L "$default_profile" ] && [ ! -e "$default_profile" ]; then
          run rm -- "$default_profile"
        fi
        if [ ! -e "$default_profile" ]; then
          run mkdir -p "$(dirname "$default_profile")"
          run ln -s "${profileSource}" "$default_profile"
        fi
      ''
    );

    xdg.configFile."hyprmoncfg/profiles/default.json" = lib.mkIf (displays.monitors != [ ]) {
      source = profileSource;
    };

    wayland.windowManager.hyprland = {
      # hyprmoncfgd owns this runtime-generated file. Keep the include in the
      # declarative Home Manager config so the root Hyprland config remains
      # store-backed and immutable.
      extraConfig = ''
        local hypr_config_dir = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
        package.path = hypr_config_dir .. "/hypr/?.lua;" .. package.path
        local monitors_file = io.open(hypr_config_dir .. "/hypr/monitors.lua", "r")
        if monitors_file then
          monitors_file:close()
          package.loaded["monitors"] = nil
          require("monitors")
        end
      '';

      settings = {
        config = {
          misc.vrr = vrrMode;
          render = {
            direct_scanout = 0;
            non_shader_cm = 0;
          }
          // lib.optionalAttrs hasHDR {
            cm_enabled = true;
            cm_sdr_eotf = "gamma22";
          };
        };
      };
    };
  };
}
