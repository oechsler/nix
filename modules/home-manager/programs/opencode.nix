# OpenCode AI Coding Agent Configuration
#
# This module configures OpenCode, an AI coding agent.
#
# Configuration:
# - Default model: openai/gpt-5.6-luna
# - Providers: OpenAI (browser login), OpenCode Go
# - API keys managed via SOPS secrets
# - Environment variables sourced in Fish shell
#
# Providers:
# - openai: OpenAI models (browser login, no API key needed)
# - opencode-go: OpenCode Go proxy models (API key from sops)
#   - DeepSeek V4 Flash/Pro
#   - GPT-5.6 Luna
#   - Qwen3.7 Plus/Max
#   - Qwen3.8 Max

{
  config,
  lib,
  features,
  pkgs,
  ...
}:

let
  cfg = features.dev.opencode;
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
      ${providerEnvName name}="$(< ${providerSecretPath provider})" \
    '') providersWithSecrets
  );
  mcpEnvAssignments = lib.concatStringsSep "" (
    lib.mapAttrsToList (name: server: ''
      ${mcpEnvName name}="$(< ${mcpSecretPath server})" \
    '') mcpWithSecrets
  );
  mcpOAuthEnvAssignments = lib.concatStringsSep "" (
    lib.mapAttrsToList (name: server: ''
      ${mcpOAuthEnvName name}="$(< ${mcpOAuthSecretPath server})" \
    '') mcpWithOAuthSecrets
  );
  providerSettings = lib.mapAttrs (
    name: provider:
    {
      models = provider.models;
    }
    // lib.optionalAttrs (provider.name != null) { name = provider.name; }
    // lib.optionalAttrs (provider.npm != null) { npm = provider.npm; }
    // lib.optionalAttrs (provider.baseURL != null || provider.apiKeySecret != null) {
      options =
        lib.optionalAttrs (provider.baseURL != null) { baseURL = provider.baseURL; }
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
    // lib.optionalAttrs (server.command != [ ]) { command = server.command; }
    // lib.optionalAttrs (server.extensions != [ ]) { extensions = server.extensions; }
    // lib.optionalAttrs (server.env != { }) { env = server.env; }
    // lib.optionalAttrs (server.initialization != { }) { initialization = server.initialization; }
  ) cfg.lsp;
  mcpSettings = lib.mapAttrs (
    name: server:
    {
      type = server.type;
      enabled = server.enable;
      timeout = server.timeout;
    }
    // lib.optionalAttrs (server.type == "remote") {
      url = server.url;
    }
    // lib.optionalAttrs (server.type == "local") {
      command = server.command;
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
    exec env \
      ${providerEnvAssignments}${mcpEnvAssignments}${mcpOAuthEnvAssignments}
      ${pkgs.opencode}/bin/opencode "$@"
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
