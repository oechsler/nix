# OpenCode AI coding agent configuration.
# Provider credentials and MCP secrets are injected at runtime from SOPS.

{
  config,
  lib,
  features,
  pkgs,
  theme,
  ...
}:

let
  cfg = features.dev.opencode;
  opencodeTheme =
    {
      latte = "catppuccin";
      frappe = "catppuccin-frappe";
      macchiato = "catppuccin-macchiato";
      mocha = "catppuccin";
    }
    .${theme.catppuccin.flavor};
  enabledProviders = lib.filterAttrs (_: provider: provider.enable) cfg.provider;
  providersWithSecrets = lib.filterAttrs (
    _: provider: provider.apiKeySecret != null
  ) enabledProviders;
  mcpWithSecrets = lib.filterAttrs (_: server: server.tokenSecret != null) cfg.mcp;
  mcpWithOAuthSecrets = lib.filterAttrs (
    _: server:
    server.type == "remote" && server.oauth != null && server.oauth.clientSecretSecret != null
  ) cfg.mcp;
  envName =
    prefix: name:
    "OPENCODE_${prefix}_${
      lib.toUpper (lib.replaceStrings [ "-" "." " " ] [ "_" "_" "_" ] name)
    }_API_KEY";
  providerEnvName = name: envName "PROVIDER" name;
  mcpEnvName =
    name: "OPENCODE_MCP_${lib.toUpper (lib.replaceStrings [ "-" "." " " ] [ "_" "_" "_" ] name)}";
  mcpOAuthEnvName = name: "${mcpEnvName name}_OAUTH_CLIENT_SECRET";
  providerSecretPath = provider: config.sops.secrets.${provider.apiKeySecret}.path;
  mcpSecretPath = server: config.sops.secrets.${server.tokenSecret}.path;
  mcpOAuthSecretPath = server: config.sops.secrets.${server.oauth.clientSecretSecret}.path;
  providerSecretChecks = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: provider: ''
      if ! test -r ${providerSecretPath provider}; then
        echo "OpenCode provider API key is missing for ${name}: run sops-install-secrets.service and check the SOPS age key" >&2
        exit 1
      fi
    '') providersWithSecrets
  );
  mcpSecretChecks = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: server: ''
      if ! test -r ${mcpSecretPath server}; then
        echo "OpenCode MCP token is missing for ${name}: run sops-install-secrets.service and check the SOPS age key" >&2
        exit 1
      fi
    '') mcpWithSecrets
  );
  mcpOAuthSecretChecks = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: server: ''
      if ! test -r ${mcpOAuthSecretPath server}; then
        echo "OpenCode MCP OAuth client secret is missing for ${name}: run sops-install-secrets.service and check the SOPS age key" >&2
        exit 1
      fi
    '') mcpWithOAuthSecrets
  );
  providerEnvAssignments = lib.concatStringsSep "" (
    lib.mapAttrsToList (name: provider: ''
      export ${providerEnvName name}="$(< ${providerSecretPath provider})"
    '') providersWithSecrets
  );
  mcpEnvAssignments = lib.concatStringsSep "" (
    lib.mapAttrsToList (name: server: ''
      export ${mcpEnvName name}="$(< ${mcpSecretPath server})"
    '') mcpWithSecrets
  );
  mcpOAuthEnvAssignments = lib.concatStringsSep "" (
    lib.mapAttrsToList (name: server: ''
      export ${mcpOAuthEnvName name}="$(< ${mcpOAuthSecretPath server})"
    '') mcpWithOAuthSecrets
  );
  defaultFormatters = {
    nixfmt = {
      command = [
        "${pkgs.nixfmt}/bin/nixfmt"
        "$FILE"
      ];
      extensions = [ ".nix" ];
    };
    prettier = {
      command = [
        "${pkgs.prettierd}/bin/prettierd"
        "$FILE"
      ];
      extensions = [
        ".js"
        ".jsx"
        ".ts"
        ".tsx"
        ".json"
        ".jsonc"
        ".yaml"
        ".yml"
        ".md"
      ];
    };
    shfmt = {
      command = [
        "${pkgs.shfmt}/bin/shfmt"
        "-w"
        "$FILE"
      ];
      extensions = [
        ".sh"
        ".bash"
        ".zsh"
      ];
    };
    ruff = {
      command = [
        "${pkgs.ruff}/bin/ruff"
        "format"
        "$FILE"
      ];
      extensions = [
        ".py"
        ".pyi"
      ];
    };
    gofumpt = {
      command = [
        "${pkgs.gofumpt}/bin/gofumpt"
        "-w"
        "$FILE"
      ];
      extensions = [ ".go" ];
    };
    rustfmt = {
      command = [
        "${pkgs.rustfmt}/bin/rustfmt"
        "$FILE"
      ];
      extensions = [ ".rs" ];
    };
    google-java-format = {
      command = [
        "${pkgs.google-java-format}/bin/google-java-format"
        "--replace"
        "$FILE"
      ];
      extensions = [ ".java" ];
    };
  };
  formatterSettings = lib.mapAttrs (
    _name: formatter:
    {
      disabled = !(formatter.enable or true);
    }
    // lib.optionalAttrs (formatter.command != [ ]) { inherit (formatter) command; }
    // lib.optionalAttrs (formatter.extensions != [ ]) { inherit (formatter) extensions; }
    // lib.optionalAttrs ((formatter.environment or { }) != { }) {
      inherit (formatter) environment;
    }
  ) (defaultFormatters // cfg.formatter);
  providerSettings = lib.mapAttrs (
    name: provider:
    {
      inherit (provider) models;
      whitelist = builtins.attrNames provider.models;
    }
    // lib.optionalAttrs (provider.name != null) { inherit (provider) name; }
    // lib.optionalAttrs (provider.npm != null) { inherit (provider) npm; }
    // lib.optionalAttrs (provider.baseURL != null || provider.apiKeySecret != null) {
      options =
        lib.optionalAttrs (provider.baseURL != null) { inherit (provider) baseURL; }
        // lib.optionalAttrs (provider.apiKeySecret != null) {
          apiKey = "{env:${providerEnvName name}}";
        };
    }
  ) enabledProviders;
  providerSopsSecrets = lib.mapAttrs' (
    _name: provider: lib.nameValuePair provider.apiKeySecret { }
  ) providersWithSecrets;
  lspSettings = lib.mapAttrs (
    _name: server:
    {
      disabled = !server.enable;
    }
    // lib.optionalAttrs (server.command != [ ]) { inherit (server) command; }
    // lib.optionalAttrs (server.extensions != [ ]) { inherit (server) extensions; }
    // lib.optionalAttrs (server.env != { }) { inherit (server) env; }
    // lib.optionalAttrs (server.initialization != { }) { inherit (server) initialization; }
  ) cfg.lsp;
  mcpSettings = lib.mapAttrs (
    name: server:
    {
      inherit (server) type;
      enabled = server.enable;
      inherit (server) timeout;
    }
    // lib.optionalAttrs (server.type == "remote") {
      inherit (server) url;
    }
    // lib.optionalAttrs (server.type == "local") {
      inherit (server) command;
    }
    // lib.optionalAttrs (server.headers != { } || server.tokenSecret != null) {
      headers =
        server.headers
        // lib.optionalAttrs (server.tokenSecret != null) {
          "${server.tokenHeader}" = "${server.tokenPrefix}{env:${mcpEnvName name}}";
        };
    }
    // lib.optionalAttrs (server.type == "remote" && server.oauth != null) {
      oauth =
        lib.optionalAttrs (server.oauth.clientId != null) {
          clientId = server.oauth.clientId;
        }
        // lib.optionalAttrs (server.oauth.clientSecretSecret != null) {
          clientSecret = "{env:${mcpOAuthEnvName name}}";
        }
        // lib.optionalAttrs (server.oauth.scope != null) { scope = server.oauth.scope; }
        // lib.optionalAttrs (server.oauth.callbackPort != null) {
          callbackPort = server.oauth.callbackPort;
        }
        // lib.optionalAttrs (server.oauth.redirectUri != null) {
          redirectUri = server.oauth.redirectUri;
        };
    }
  ) cfg.mcp;
  mcpSopsSecrets = lib.mapAttrs' (
    _name: server: lib.nameValuePair server.tokenSecret { }
  ) mcpWithSecrets;
  mcpOAuthSopsSecrets = lib.mapAttrs' (
    _name: server: lib.nameValuePair server.oauth.clientSecretSecret { }
  ) mcpWithOAuthSecrets;
  opencodeWithSecrets = pkgs.writeShellScriptBin "opencode" ''
    ${providerSecretChecks}
    ${mcpSecretChecks}
    ${mcpOAuthSecretChecks}
    ${providerEnvAssignments}${mcpEnvAssignments}${mcpOAuthEnvAssignments}
    exec ${pkgs.opencode}/bin/opencode "$@"
  '';
  opencodeServer = pkgs.writeShellScriptBin "opencode-server" ''
    exec ${opencodeWithSecrets}/bin/opencode serve \
      --hostname 127.0.0.1 \
      --port 4096
  '';
in
{
  config = lib.mkIf (features.dev.enable && features.dev.opencode.enable) {
    sops.secrets = providerSopsSecrets // mcpSopsSecrets // mcpOAuthSopsSecrets;

    programs.opencode = {
      enable = true;
      package = opencodeWithSecrets;

      settings = cfg.settings // {
        lsp = {
          # Add locally managed servers for formats not covered by the built-ins.
          markdown = {
            command = [
              "${pkgs.marksman}/bin/marksman"
              "server"
            ];
            extensions = [ ".md" ];
          };
          json = {
            command = [
              "${pkgs.vscode-json-languageserver}/bin/vscode-json-language-server"
              "--stdio"
            ];
            extensions = [
              ".json"
              ".jsonc"
            ];
          };
          toml = {
            command = [
              "${pkgs.taplo}/bin/taplo"
              "lsp"
              "stdio"
            ];
            extensions = [ ".toml" ];
          };
        }
        // lspSettings;
        formatter = formatterSettings;
        enabled_providers = builtins.attrNames enabledProviders;
        theme = cfg.settings.theme or opencodeTheme;
        model = cfg.defaultModel;
        small_model = cfg.settings.small_model or cfg.defaultModel;

        mcp = mcpSettings;

        compaction =
          cfg.settings.compaction or {
            auto = true;
            prune = true;
            reserved = 20000;
          };

        provider = providerSettings;
      };
    };

    systemd.user.services.opencode-server = lib.mkIf cfg.server.enable {
      Unit = {
        Description = "OpenCode background server";
        After = [ "sops-nix.service" ];
      };
      Service = {
        Type = "exec";
        ExecStart = "${opencodeServer}/bin/opencode-server";
        WorkingDirectory = cfg.server.directory;
        ProtectHome = "tmpfs";
        BindPaths = [
          cfg.server.directory
          "${config.home.homeDirectory}/.local"
          "${config.home.homeDirectory}/.cache"
        ];
        BindReadOnlyPaths = [
          "${config.xdg.configHome}/opencode"
          "${config.xdg.configHome}/sops-nix/secrets"
        ];
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
