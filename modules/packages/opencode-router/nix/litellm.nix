{
  config,
  lib,
  pkgs,
  features,
  ...
}:

let
  cfg = config.programs.opencode-router;

  apiKeyEnvForModel =
    litellmModel:
    let
      prefix = lib.head (lib.splitString "/" litellmModel);
    in
    {
      mistral = "MISTRAL_API_KEY";
      openai = "OPENCODE_GO_API_KEY";
    }
    .${prefix} or "LITELLM_API_KEY";

  litellmModels = lib.filterAttrs (
    n: m: m.provider == "litellm" && m.litellmModel != null
  ) cfg.models;

  litellmModelList = lib.mapAttrsToList (name: model: {
    model_name = name;
    litellm_params = {
      model = model.litellmModel;
      api_key = "os.environ/${apiKeyEnvForModel model.litellmModel}";
    }
    // lib.optionalAttrs (model.litellmApiBase != null) {
      api_base = model.litellmApiBase;
    };
  }) litellmModels;

  litellmYaml = pkgs.writeText "litellm.yaml" (
    builtins.toJSON {
      model_list = litellmModelList;
      litellm_settings = {
        drop_params = true;
        request_timeout = 600;
      };
      general_settings = {
        master_key = "dummy";
      };
    }
  );
in
{
  config =
    lib.mkIf (features.development.enable && features.development.opencode.enable && cfg.enable)
      {
        programs.opencode-router.litellmConfigFile = lib.mkDefault litellmYaml;
      };
}
