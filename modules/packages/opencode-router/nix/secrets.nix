{
  config,
  lib,
  features,
  ...
}:

let
  cfg = config.programs.opencode-router;

  secretKeys = lib.mapAttrs' (envVar: sopsPath: lib.nameValuePair sopsPath { }) cfg.litellmApiKeys;

  envContent = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      envVar: sopsPath: "${envVar}=${config.sops.placeholder.${sopsPath}}"
    ) cfg.litellmApiKeys
  );
in
{
  config =
    lib.mkIf (features.development.enable && features.development.opencode.enable && cfg.enable)
      {
        sops.secrets = secretKeys;

        sops.templates."opencode-router-litellm.env" = {
          content = envContent;
        };
      };
}
