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
  mcpWithSecrets = lib.filterAttrs (_: server: server.enable && server.tokenSecret != null) cfg.mcp;
  envName =
    prefix: name:
    "OPENCODE_${prefix}_${
      lib.toUpper (lib.replaceStrings [ "-" "." " " ] [ "_" "_" "_" ] name)
    }_API_KEY";
  providerEnvName = name: envName "PROVIDER" name;
  mcpEnvName =
    name: "OPENCODE_MCP_${lib.toUpper (lib.replaceStrings [ "-" "." " " ] [ "_" "_" "_" ] name)}";
  providerSecretPath = provider: config.sops.secrets.${provider.apiKeySecret}.path;
  mcpSecretPath = server: config.sops.secrets.${server.tokenSecret}.path;
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
  ) cfg.mcp;
  mcpSopsSecrets = lib.mapAttrs' (
    _name: server: lib.nameValuePair server.tokenSecret { }
  ) mcpWithSecrets;
  opencodeWithSecrets = pkgs.writeShellScriptBin "opencode" ''
    ${providerSecretChecks}
    ${mcpSecretChecks}
    exec env \
      ${providerEnvAssignments}${mcpEnvAssignments}
      ${pkgs.opencode}/bin/opencode "$@"
  '';
in
{
  config = lib.mkIf (features.dev.enable && features.dev.opencode.enable) {
    sops.secrets = providerSopsSecrets // mcpSopsSecrets;

    programs.opencode = {
      enable = true;
      package = opencodeWithSecrets;

      settings = {
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
        };
        model = cfg.defaultModel;

        mcp = mcpSettings;

        compaction = {
          auto = true;
          prune = true;
          reserved = 20000;
        };

        provider = providerSettings;
      };
    };
  };
}
