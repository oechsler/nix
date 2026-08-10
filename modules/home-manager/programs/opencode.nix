# OpenCode AI Coding Agent Configuration
#
# This module configures OpenCode, an AI coding agent.
#
# Configuration:
# - Default model: mistral/mistral-medium-latest
# - Providers: Mistral, OpenAI (browser login), OpenCode Go
# - API keys managed via SOPS secrets
# - Environment variables sourced in Fish shell
#
# Providers:
# - mistral: Mistral AI models (API key from sops)
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
  opencodeWithSecrets = pkgs.writeShellScriptBin "opencode" ''
    exec env \
      MISTRAL_API_KEY="$(< ${config.sops.secrets."opencode/mistral/api-key".path})" \
      OPENCODE_GO_API_KEY="$(< ${config.sops.secrets."opencode/opencode-go/api-key".path})" \
      ${pkgs.opencode}/bin/opencode "$@"
  '';
in
{
  config = lib.mkIf (features.development.enable && features.development.opencode.enable) {
    sops.secrets = {
      "opencode/mistral/api-key" = { };
      "opencode/opencode-go/api-key" = { };
    };

    programs.opencode = {
      enable = true;
      package = opencodeWithSecrets;

      settings = {
        lsp = true;
        model = "mistral/mistral-medium-latest";

        compaction = {
          auto = true;
          prune = true;
          reserved = 20000;
        };

        provider = {
          mistral = { };

          openai = { };

          "opencode-go" = {
            npm = "@ai-sdk/openai-compatible";
            name = "OpenCode Go";
            options = {
              baseURL = "https://opencode.ai/zen/go/v1";
            };
            models = {
              "deepseek-v4-flash" = {
                name = "DeepSeek V4 Flash";
              };
              "deepseek-v4-pro" = {
                name = "DeepSeek V4 Pro";
              };
              "gpt-5.6-luna" = {
                name = "GPT-5.6 Luna";
              };
              "qwen3.7-plus" = {
                name = "Qwen3.7 Plus";
              };
              "qwen3.7-max" = {
                name = "Qwen3.7 Max";
              };
              "qwen3.8-max" = {
                name = "Qwen3.8 Max";
              };
            };
          };
        };
      };
    };
  };
}
