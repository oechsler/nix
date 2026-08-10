{
  config,
  lib,
  features,
  ...
}:

let
  cfg = config.programs.opencode-router;
in
{
  config =
    lib.mkIf (features.development.enable && features.development.opencode.enable && cfg.enable)
      {
        sops.secrets = {
          "opencode/mistral/api-key" = { };
          "opencode/opencode-go/api-key" = { };
        };

        sops.templates."opencode-router-litellm.env" = {
          content = ''
            MISTRAL_API_KEY=${config.sops.placeholder."opencode/mistral/api-key"}
            OPENCODE_GO_API_KEY=${config.sops.placeholder."opencode/opencode-go/api-key"}
          '';
        };
      };
}
