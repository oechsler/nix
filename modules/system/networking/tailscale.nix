# Tailscale VPN Configuration
#
# Mesh VPN with system tray applet on desktop hosts.
# Active when features.tailscale.enable = true.

{ config, pkgs, lib, ... }:

let
  tailscaleCfg = config.features.tailscale;
in
{
  config = lib.mkIf tailscaleCfg.enable {
    services.tailscale.enable = true;

    networking.firewall.trustedInterfaces = [ "tailscale0" ];

    environment.systemPackages =
      [
        (pkgs.writeShellScriptBin "tailscale-init" ''
          set -e
          echo "Starting Tailscale login..."
          sudo tailscale up --accept-routes --accept-dns
          echo "Setting operator to ${config.user.name}..."
          sudo tailscale set --operator=${config.user.name}
          echo "Done! Tailscale is ready."
          tailscale status
        '')
      ]
      ++ lib.optionals config.features.desktop.enable [
        pkgs.trayscale
      ];
  };
}
