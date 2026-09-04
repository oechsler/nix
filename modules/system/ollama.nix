# Ollama local model server feature.

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.features.dev.ollama;
  ollama = lib.getExe config.services.ollama.package;
  curl = lib.getExe pkgs.curl;
  ollamaUrl = "http://127.0.0.1:${toString config.services.ollama.port}";
  declaredModels = lib.escapeShellArgs cfg.models;
in
{
  options.features.dev.ollama = {
    enable = (lib.mkEnableOption "Ollama local model server") // {
      default = false;
    };

    server = lib.mkEnableOption "Ollama API access from other hosts";

    models = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "gemma3:12b"
        "qwen3:8b"
      ];
      description = "Ollama models to pull declaratively after the server starts.";
    };
  };

  config = lib.mkIf (config.features.dev.enable && cfg.enable) {
    environment.systemPackages = [ config.services.ollama.package ];

    services.ollama = {
      enable = true;
      loadModels = cfg.models;
      syncModels = true;
      host = if cfg.server then "0.0.0.0" else "127.0.0.1";
      openFirewall = cfg.server;
    };

    # Consume the API's NDJSON stream so progress works without a TTY.
    systemd.services.ollama-model-loader.script = lib.mkForce ''
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
            if .error then error(.error)
            elif (.completed? and .total?) then
              "\(.status): \((100 * .completed / .total) | floor)% \(.completed)/\(.total)"
            else .status // empty
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
    systemd.services.ollama-model-loader.environment.SHELL = lib.getExe pkgs.bash;
  };
}
