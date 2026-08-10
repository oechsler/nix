{
  config,
  lib,
  pkgs,
  features,
  ...
}:

let
  cfg = config.programs.opencode-router;

  litellmModels = lib.filterAttrs (
    n: m: m.provider == "litellm" && m.backend.litellm.model != null
  ) cfg.models;

  litellmModelList = lib.mapAttrsToList (name: model: {
    model_name = name;
    litellm_params = {
      model = model.backend.litellm.model;
      api_key = "os.environ/${model.backend.litellm.apiKeyEnv}";
    }
    // lib.optionalAttrs (model.backend.litellm.apiBase != null) {
      api_base = model.backend.litellm.apiBase;
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
