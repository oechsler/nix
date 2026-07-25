# OpenCode client configuration for the local auto-router provider.
{
  features,
  lib,
  ...
}:

let
  model = name: {
    inherit name;
    reasoning = true;
    interleaved.field = "reasoning_content";
    tool_call = true;
    temperature = true;
    limit = {
      context = 128000;
      output = 32768;
    };
  };
in
{
  config = lib.mkIf (features.development.enable && features.development.opencode.enable) {
    programs.opencode = {
      enable = true;

      settings = {
        enabled_providers = [
          "local"
          "openai"
        ];

        model = "local/auto";
        small_model = "local/auto";

        # Keep long tool-heavy sessions usable without imposing an agent step limit.
        compaction = {
          auto = true;
          prune = true;
          reserved = 20000;
        };

        agent = {
          build.model = "local/auto";
          general.model = "local/auto";
          explore.model = "local/auto";
          plan.model = "local/auto";
          title.model = "local/mistral-small";
          summary.model = "local/mistral-small";
        };

        provider.local = {
          npm = "@ai-sdk/openai-compatible";
          name = "Local";
          options = {
            baseURL = "http://127.0.0.1:4000/v1";
            apiKey = "dummy";
            timeout = 600000;
          };
          models = {
            auto = model "Auto";
            mistral-small = model "Mistral Small";
            mistral-medium = model "Mistral Medium";
            deepseek-v4-pro = model "DeepSeek V4 Pro";
            deepseek-v4-flash = model "DeepSeek V4 Flash";
            "qwen3.7-max" = model "Qwen3.7 Max";
            "qwen3.7-plus" = model "Qwen3.7 Plus";
            "qwen3.6-plus" = model "Qwen3.6 Plus";
            openai-luna-fast = model "ChatGPT 5.6 Luna Fast";
            openai-luna = model "ChatGPT 5.6 Luna";
            openai-sol-fast = model "ChatGPT 5.6 Sol Fast";
            openai-sol = model "ChatGPT 5.6 Sol";
            openai-terra-fast = model "ChatGPT 5.6 Terra Fast";
            openai-terra = model "ChatGPT 5.6 Terra";
          }
          // lib.optionalAttrs (features.development.opencode.classifier == "local") {
            "qwen3:8b" = model "Qwen3 8B (Local)";
          };
        };
      };
    };
  };
}
