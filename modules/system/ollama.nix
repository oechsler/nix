# Ollama local model server feature.
#
# The model loader keeps declared models synchronized and reports the streaming
# pull status returned by Ollama.

{
  config,
  lib,
  pkgs,
  ...
}:

let
  modelSpec = import ../lib/opencode.nix { inherit lib; };
  cfg = config.features.dev.ollama;
  ollamaPackage =
    if config.features.hardware.gpu == "amd" then
      pkgs.ollama-rocm
    else if config.features.hardware.gpu == "intel" then
      pkgs.ollama-vulkan
    else
      pkgs.ollama;
  ollama = lib.getExe config.services.ollama.package;
  curl = lib.getExe pkgs.curl;
  ollamaUrl = "http://127.0.0.1:${toString config.services.ollama.port}";
  declaredModels = lib.escapeShellArgs (builtins.attrNames cfg.models);
in
{
  options.features.dev.ollama = {
    enable = (lib.mkEnableOption "Ollama local model server") // {
      default = false;
    };

    server = lib.mkEnableOption "Ollama API access from other hosts";

    unloadAfter = lib.mkOption {
      type = lib.types.str;
      default = "5m";
      example = "5m";
      description = "How long Ollama keeps an inactive model loaded.";
    };

    context = lib.mkOption {
      type = lib.types.ints.positive;
      default = 32768;
      example = 131072;
      description = "Default context length in tokens for Ollama model servers.";
    };

    models = lib.mkOption {
      type = lib.types.coercedTo (lib.types.listOf lib.types.str) (
        models:
        lib.genAttrs models (model: {
          name = model;
        })
      ) (lib.types.attrsOf modelSpec.type);
      default = { };
      example = {
        "gemma3:12b".name = "Gemma 3 12B";
        "qwen3:8b".name = "Qwen3 8B";
      };
      description = "Ollama models to pull declaratively, keyed by model ID.";
    };
  };

  config = lib.mkIf (config.features.dev.enable && cfg.enable) {
    environment.systemPackages = [ config.services.ollama.package ];

    systemd.tmpfiles.rules = [
      "d /var/lib/ollama 0750 ollama ollama -"
      "d /var/lib/ollama/models 0750 ollama ollama -"
    ];

    services.ollama = {
      enable = true;
      package = ollamaPackage;
      user = "ollama";
      group = "ollama";
      loadModels = builtins.attrNames cfg.models;
      syncModels = true;
      host = if cfg.server then "0.0.0.0" else "127.0.0.1";
      openFirewall = cfg.server;
      environmentVariables.OLLAMA_KEEP_ALIVE = cfg.unloadAfter;
      environmentVariables.OLLAMA_CONTEXT_LENGTH = toString cfg.context;
    };
    systemd.services = {
      ollama.serviceConfig.DynamicUser = lib.mkForce false;

      # Consume the API's NDJSON stream so progress works without a TTY.
      ollama-model-loader = {
        script = lib.mkForce ''
          installed="$(${ollama} list | ${lib.getExe pkgs.gawk} 'NR > 1 {print $1}')"
          for model in $installed; do
            declared=false
            for declared_model in ${declaredModels}; do
              if [ "$model" = "$declared_model" ]; then
                declared=true
                break
              fi
            done
            if [ "$declared" = false ]; then
              echo "removing model: $model"
              ${ollama} rm "$model"
            fi
          done

          for model in ${declaredModels}; do
            echo "pulling model: $model"
            payload="$(${lib.getExe pkgs.jq} -cn --arg model "$model" '{name: $model}')"
            set +e
            ${curl} --no-buffer --fail-with-body -sS \
              -X POST "${ollamaUrl}/api/pull" \
              -H 'Content-Type: application/json' \
              --data "$payload" \
               | ${lib.getExe pkgs.jq} -r '
                 objects
                 | if (.error? != null) then error(.error | tostring)
                   elif (.completed? != null and .total? != null and (.total | tonumber) > 0) then
                     "\(.status): \((100 * (.completed | tonumber) / (.total | tonumber)) | floor)% \(.completed)/\(.total)"
                   else .status? // empty
                   end
               '
            status=''${PIPESTATUS[0]}
            set -e
            if [ "$status" -ne 0 ]; then
              exit "$status"
            fi
            echo "finished model: $model"
          done
        '';
        environment.SHELL = lib.getExe pkgs.bash;
      };
    };
  };
}
