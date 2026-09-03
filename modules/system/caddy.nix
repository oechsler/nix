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
  caddyRootCertificateExport = "${config.services.caddy.dataDir}/root.crt";
  caBundle = "${config.services.caddy.dataDir}/ca-bundle.crt";
  browser = config.features.desktop.browser.type;
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
      domain = "opencode.caddy";
      upstream = "127.0.0.1:4096";
    };

    networking.extraHosts = lib.mkIf (endpoints != { }) extraHosts;

    services.caddy = lib.mkIf (endpoints != { }) {
      enable = true;
      extraConfig = caddyConfig;
    };

    home-manager.users.${config.user.name}.programs.${browser}.policies.Certificates.Install =
      lib.mkIf (endpoints != { })
        [ caddyRootCertificateExport ];

    systemd.services.caddy-trust = lib.mkIf (endpoints != { }) {
      description = "Trust Caddy's local CA";
      wantedBy = [ "multi-user.target" ];
      after = [ "caddy.service" ];
      requires = [ "caddy.service" ];
      path = [
        pkgs.coreutils
        pkgs.curl
        pkgs.jq
      ];
      serviceConfig = {
        Type = "oneshot";
        Environment = [
          "HOME=${config.services.caddy.dataDir}"
          "XDG_CONFIG_HOME=${config.services.caddy.dataDir}/.config"
        ];
      };
      script = ''
        attempts=0
        while [ "$attempts" -lt 30 ]; do
          if curl --fail --silent --show-error http://127.0.0.1:2019/pki/ca/local \
            | jq --exit-status --raw-output .root_certificate > "${caddyRootCertificateExport}.tmp" \
            && [ -s "${caddyRootCertificateExport}.tmp" ]; then
            break
          fi
          attempts=$((attempts + 1))
          sleep 1
        done

        if [ ! -s "${caddyRootCertificateExport}.tmp" ]; then
          echo "Caddy local root certificate was not available through the admin API" >&2
          exit 1
        fi

        mv -f "${caddyRootCertificateExport}.tmp" "${caddyRootCertificateExport}"
        cat "${config.security.pki.caBundle}" "${caddyRootCertificateExport}" > "${caBundle}.tmp"
        chmod 0644 "${caBundle}.tmp"
        mv -f "${caBundle}.tmp" "${caBundle}"
      '';
    };

    environment.variables = lib.mkIf (endpoints != { }) {
      CURL_CA_BUNDLE = caBundle;
      NIX_SSL_CERT_FILE = caBundle;
      SSL_CERT_FILE = caBundle;
    };
  };
}
