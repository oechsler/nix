# Tailscale VPN Configuration
#
# Mesh VPN with system tray applet on desktop hosts.
# Active when features.tailscale.enable = true.

{
  config,
  pkgs,
  lib,
  ...
}:

let
  tailscaleCfg = config.features.tailscale;
in
{
  config = lib.mkIf tailscaleCfg.enable {
    services.tailscale = {
      enable = true;
      port = 41641;
    };

    networking.firewall.allowedUDPPorts = [ 41641 ];

    environment.systemPackages = [
      (pkgs.writeShellScriptBin "tailscale-init" ''
        set -eu

        tailscale_command() {
           ${pkgs.sudo}/bin/sudo ${pkgs.tailscale}/bin/tailscale "$@"
        }

        echo "Starting Tailscale login..."
        tailscale_command up --accept-routes --accept-dns
        echo "Setting operator to ${config.user.name}..."
        tailscale_command set --operator=${lib.escapeShellArg config.user.name}
        echo "Done! Tailscale is ready."
        ${pkgs.tailscale}/bin/tailscale status
      '')
    ]
    ++ lib.optionals config.features.desktop.enable [
      pkgs.trayscale
    ];
  };
}
