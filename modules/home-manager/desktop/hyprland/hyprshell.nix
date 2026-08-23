# Hyprshell window switcher
#
# Rust/GTK4 switcher with real modifier-release behavior, MRU ordering, and
# workspace-aware window switching. Super+W remains the Rofi window list.

{
  config,
  lib,
  pkgs,
  fonts,
  theme,
  ...
}:

let
  palette = config.theme.catppuccinPalette;
  stripHash = value: builtins.substring 1 6 value;
  hyprshell = pkgs.hyprshell.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace crates/windows-lib/src/shared/workspaces.rs \
        --replace-fail 'set_cursor_from_name: Some("pointer"),' "" \
        --replace-fail 'connect_clicked[sender, id = self.workspace_id] => move |_| sender.output_sender().emit(WorkspacesOutput::Clicked(id)),' ""
      substituteInPlace crates/windows-lib/src/shared/workspace_clients.rs \
        --replace-fail 'set_cursor_from_name: Some("pointer"),' "" \
        --replace-fail 'connect_clicked[sender, id = self.id] => move |_| sender.output_sender().emit(WorkspaceClientsOutput::Clicked(id)),' ""
    '';
  });
  hyprshellConfig = pkgs.writeText "hyprshell-config.json" (
    builtins.toJSON {
      version = 4;
      windows = {
        switch = {
          modifier = "super";
          key = "Tab";
          filter_by = [ ];
          switch_workspaces = true;
        };
      };
    }
  );
  hyprshellStyle = pkgs.writeText "hyprshell-style.css" ''
    @define-color base ${palette.base.hex};
    @define-color surface0 ${palette.surface0.hex};
    @define-color surface1 ${palette.surface1.hex};
    @define-color text ${palette.text.hex};

    :root {
      --bg-window-color: alpha(@base, ${lib.strings.floatToString theme.alpha.container});
      --workspace-color: transparent;
      --client-color: alpha(@text, ${lib.strings.floatToString theme.alpha.inactive});
      --bg-color-hover: alpha(@surface1, ${lib.strings.floatToString theme.alpha.hover});
      --text-color: @text;
      --border-color: @surface1;
      --border-color-active: #${stripHash palette.${config.catppuccin.accent}.hex};
      --border-radius: ${toString theme.radius.default}px;
      --border-size: ${toString theme.border.width}px;
      --window-padding: ${toString theme.gaps.outer}px;
    }

    * {
      font-family: "${fonts.ui}";
    }

    .window {
      background: transparent;
      background-color: transparent;
      padding: ${toString theme.gaps.inner}px;
    }

    .monitor {
      background: var(--bg-window-color);
      box-shadow: none;
      border: ${toString theme.border.width}px solid #${
        stripHash palette.${config.catppuccin.accent}.hex
      };
      border-radius: ${toString theme.radius.default}px;
      padding: ${toString theme.gaps.outer}px;
    }

    .client,
    .workspace {
      border: ${toString theme.border.width}px solid var(--border-color);
      border-radius: ${toString theme.radius.default}px;
      color: var(--text-color);
      padding: ${toString theme.gaps.inner}px;
      transition: 150ms ease;
    }

    .workspace {
      background: var(--workspace-color);
    }

    .client {
      background: var(--client-color);
      border: none;
    }

    .client.active,
    .workspace.active {
      border-color: #${stripHash palette.${config.catppuccin.accent}.hex};
      color: var(--text-color);
    }

    .workspace.active {
      background: var(--workspace-color);
    }

    .client.active {
      background: var(--client-color);
    }

    .workspace:hover {
      background: var(--workspace-color);
    }

    .client:hover {
      background: var(--client-color);
    }

    .workspace.active:hover {
      background: var(--workspace-color);
    }

    .client.active:hover {
      background: var(--client-color);
    }

    .client-image {
      margin-top: ${toString (theme.gaps.inner / 2)}px;
      margin-bottom: ${toString (theme.gaps.inner / 2)}px;
    }
  '';
in

{
  home.packages = [ hyprshell ];

  xdg.configFile."hyprshell/config.json".source = hyprshellConfig;
  xdg.configFile."hyprshell/styles.css".source = hyprshellStyle;

  systemd.user.services.hyprshell = {
    Unit = {
      Description = "Hyprshell window switcher";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
      X-Restart-Triggers = [
        hyprshellConfig
        hyprshellStyle
      ];
    };
    Service = {
      ExecStart = "${hyprshell}/bin/hyprshell run";
      Environment = "PATH=/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
