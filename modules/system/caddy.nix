# Central Caddy reverse-proxy configuration for local service endpoints.

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.features.dev.opencode;
  endpoints = config.services.localEndpoints;
  # Caddy issues local certificates and handles HTTP-to-HTTPS redirects.
  caddyConfig = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (_name: endpoint: ''
      ${endpoint.domain} {
        tls internal
        reverse_proxy ${endpoint.upstream}
      }
    '') endpoints
  );
  extraHosts = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (_name: endpoint: "127.0.0.1 ${endpoint.domain}") endpoints
  );
in
{
  options.services.localEndpoints = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          domain = lib.mkOption {
            type = lib.types.str;
            description = "Hostname for this local reverse-proxy endpoint.";
          };
          upstream = lib.mkOption {
            type = lib.types.str;
            description = "Upstream address for this local endpoint.";
          };
        };
      }
    );
    default = { };
    description = "Local services exposed through the central Caddy instance.";
  };

  config = {
    services.localEndpoints.opencode = lib.mkIf cfg.server.enable {
      domain = "opencode.local";
      upstream = "127.0.0.1:4096";
    };

    networking.extraHosts = lib.mkIf (endpoints != { }) extraHosts;

    services.caddy = lib.mkIf (endpoints != { }) {
      enable = true;
      extraConfig = caddyConfig;
    };

    systemd.services.caddy-trust = lib.mkIf (endpoints != { }) {
      description = "Trust Caddy's local CA";
      wantedBy = [ "multi-user.target" ];
      after = [ "caddy.service" ];
      requires = [ "caddy.service" ];
      path = [ pkgs.p11-kit ];
      serviceConfig = {
        Type = "oneshot";
        Environment = [
          "HOME=${config.services.caddy.dataDir}"
          "XDG_CONFIG_HOME=${config.services.caddy.dataDir}/.config"
        ];
        ExecStart = "${lib.getExe config.services.caddy.package} trust --address 127.0.0.1:2019";
      };
    };

    systemd.paths.caddy-trust = lib.mkIf (endpoints != { }) {
      description = "Watch Caddy's local CA for rotation";
      wantedBy = [ "multi-user.target" ];
      after = [ "caddy.service" ];
      pathConfig = {
        PathChanged = [
          "${config.services.caddy.dataDir}/.local/share/caddy/pki/authorities/local/root.crt"
        ];
        Unit = "caddy-trust.service";
      };
    };
  };
}
