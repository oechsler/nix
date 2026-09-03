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
  mcpWithInsecureTls = lib.any (server: server.insecureTls) (lib.attrValues cfg.mcp);
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
  defaultLsp = {
    nixd = {
      command = [
        "${pkgs.nixd}/bin/nixd"
        "--stdio"
      ];
      extensions = [ ".nix" ];
    };
    bash-language-server = {
      command = [
        "${pkgs.bash-language-server}/bin/bash-language-server"
        "start"
      ];
      extensions = [
        ".sh"
        ".bash"
        ".zsh"
      ];
    };
    fish-lsp = {
      command = [
        "${pkgs.fish-lsp}/bin/fish-lsp"
        "start"
      ];
      extensions = [ ".fish" ];
    };
    yaml-language-server = {
      command = [
        "${pkgs.yaml-language-server}/bin/yaml-language-server"
        "--stdio"
      ];
      extensions = [
        ".yaml"
        ".yml"
      ];
    };
    pyright = {
      command = [
        "${pkgs.pyright}/bin/pyright-langserver"
        "--stdio"
      ];
      extensions = [ ".py" ];
    };
    gopls = {
      command = [ "${pkgs.gopls}/bin/gopls" ];
      extensions = [ ".go" ];
    };
    rust-analyzer = {
      command = [ "${pkgs.rust-analyzer}/bin/rust-analyzer" ];
      extensions = [ ".rs" ];
    };
    typescript-language-server = {
      command = [
        "${pkgs.typescript-language-server}/bin/typescript-language-server"
        "--stdio"
      ];
      extensions = [
        ".js"
        ".jsx"
        ".ts"
        ".tsx"
      ];
    };
    jdtls = {
      command = [ "${pkgs.jdt-language-server}/bin/jdtls" ];
      extensions = [ ".java" ];
    };
    kotlin-language-server = {
      command = [ "${pkgs.kotlin-language-server}/bin/kotlin-language-server" ];
      extensions = [
        ".kt"
        ".kts"
      ];
    };
    clangd = {
      command = [ "${pkgs.clang-tools}/bin/clangd" ];
      extensions = [
        ".c"
        ".h"
        ".cc"
        ".cpp"
        ".cxx"
        ".hpp"
      ];
    };
    marksman = {
      command = [
        "${pkgs.marksman}/bin/marksman"
        "server"
      ];
      extensions = [ ".md" ];
    };
    vscode-json-language-server = {
      command = [
        "${pkgs.vscode-json-languageserver}/bin/vscode-json-language-server"
        "--stdio"
      ];
      extensions = [
        ".json"
        ".jsonc"
      ];
    };
    taplo = {
      command = [
        "${pkgs.taplo}/bin/taplo"
        "lsp"
        "stdio"
      ];
      extensions = [ ".toml" ];
    };
  };
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
    fish_indent = {
      command = [
        "${pkgs.fish}/bin/fish_indent"
        "-w"
        "$FILE"
      ];
      extensions = [ ".fish" ];
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
    ktlint = {
      command = [
        "${pkgs.ktlint}/bin/ktlint"
        "-F"
        "$FILE"
      ];
      extensions = [
        ".kt"
        ".kts"
      ];
    };
    clang-format = {
      command = [
        "${pkgs.clang-tools}/bin/clang-format"
        "-i"
        "$FILE"
      ];
      extensions = [
        ".c"
        ".h"
        ".cc"
        ".cpp"
        ".cxx"
        ".hpp"
      ];
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
      disabled = !(server.enable or true);
    }
    // lib.optionalAttrs (server.command != [ ]) { inherit (server) command; }
    // lib.optionalAttrs (server.extensions != [ ]) { inherit (server) extensions; }
    // lib.optionalAttrs ((server.env or { }) != { }) { inherit (server) env; }
    // lib.optionalAttrs ((server.initialization or { }) != { }) {
      inherit (server) initialization;
    }
  ) (defaultLsp // cfg.lsp);
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
    ${lib.optionalString mcpWithInsecureTls ''
      # OpenCode has no per-remote-MCP TLS exception; this affects this process.
      export NODE_TLS_REJECT_UNAUTHORIZED=0
    ''}
    ${providerSecretChecks}
    ${mcpSecretChecks}
    ${mcpOAuthSecretChecks}
    ${providerEnvAssignments}${mcpEnvAssignments}${mcpOAuthEnvAssignments}
    exec ${pkgs.opencode}/bin/opencode "$@"
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

  };
}
