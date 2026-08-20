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
  opencodeWithSecrets = pkgs.writeShellScriptBin "opencode" ''
    exec env \
      OPENCODE_GO_API_KEY="$(< ${config.sops.secrets."opencode/opencode-go/api-key".path})" \
      ${pkgs.opencode}/bin/opencode "$@"
  '';
in
{
  config = lib.mkIf (features.dev.enable && features.dev.opencode.enable) {
    sops.secrets = {
      "opencode/opencode-go/api-key" = { };
    };

    programs.opencode = {
      enable = true;
      package = opencodeWithSecrets;

      settings = {
        lsp = true;
        model = "openai/gpt-5.6-luna";

        compaction = {
          auto = true;
          prune = true;
          reserved = 20000;
        };

        provider = {
          openai = {
            models = {
              "gpt-5.6-luna" = {
                name = "GPT-5.6 Luna";
              };
            };
          };

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
