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

  directModels = lib.filterAttrs (n: m: m.direct.enable or false) cfg.models;

  directModelsByProvider = lib.groupBy (m: m.direct.provider or "unknown") (
    lib.attrValues directModels
  );

  mkProviderConfig =
    provider: models:
    let
      firstModel = lib.head models;
      getModelId =
        m:
        if m.backend.litellm.model != null then
          m.backend.litellm.model
        else if m.backend.chatgpt.model != null then
          m.backend.chatgpt.model
        else
          "unknown";
      modelConfigs = lib.listToAttrs (
        map (m: {
          name = getModelId m;
          value = {
            name = m.displayName or "Direct";
            reasoning = true;
            interleaved.field = "reasoning_content";
            tool_call = true;
            temperature = true;
            limit = {
              context = 128000;
              output = 32768;
            };
          };
        }) models
      );
    in
    {
      npm = "@ai-sdk/openai-compatible";
      name = provider;
      options = lib.mkMerge [
        { baseURL = firstModel.direct.base; }
        (lib.mkIf (firstModel.backend.litellm.apiKeyEnv != null) {
          apiKey = "\${env:" + firstModel.backend.litellm.apiKeyEnv + "}";
        })
      ];
      models = modelConfigs;
    };

  directProviderConfigs = lib.mapAttrs mkProviderConfig directModelsByProvider;

  hasOpenAiDirect = directProviderConfigs ? openai;
  otherDirectProviders = lib.removeAttrs directProviderConfigs [ "openai" ];
in
{
  config =
    lib.mkIf (features.development.enable && features.development.opencode.enable && cfg.enable)
      {
        programs.opencode = {
          enable = true;

          settings = lib.mkMerge [
            {
              lsp = true;

              enabled_providers = [
                "local"
                "openai"
              ]
              ++ (lib.attrNames otherDirectProviders);

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

              provider.openai = lib.mkIf hasOpenAiDirect directProviderConfigs.openai;
            }
            (lib.mapAttrs' (name: config: {
              name = "provider.${name}";
              value = config;
            }) otherDirectProviders)
          ];
        };
      };
}
