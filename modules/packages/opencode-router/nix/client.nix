{
  config,
  lib,
  features,
  ...
}:

let
  cfg = config.programs.opencode-router;

  clientModels = lib.mapAttrs (name: model: {
    name = model.displayName or name;
    reasoning = true;
    interleaved.field = "reasoning_content";
    tool_call = true;
    temperature = true;
    limit = {
      context = 128000;
      output = 32768;
    };
  }) (lib.filterAttrs (n: m: !m.hidden) cfg.models);

  autoModel = {
    name = "Auto";
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
  config =
    lib.mkIf (features.development.enable && features.development.opencode.enable && cfg.enable)
      {
        programs.opencode = {
          enable = true;

          settings = {
            lsp = true;

            enabled_providers = [
              "local"
              "openai"
            ];

            model = "local/auto";
            small_model = "local/auto";

            compaction = {
              auto = true;
              prune = true;
              reserved = 20000;
            };

            agent = {
              build = {
                model = "local/auto";
                steps = 1000;
              };
              general = {
                model = "local/auto";
                steps = 1000;
              };
              explore = {
                model = "local/auto";
                steps = 1000;
              };
              plan = {
                model = "local/auto";
                steps = 1000;
              };
              title.model = "local/auto";
              summary.model = "local/auto";
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
                auto = autoModel;
              }
              // clientModels;
            };
          };
        };
      };
}
