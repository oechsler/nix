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

    # Give Ollama a pseudo-TTY so it emits progress, then make it journal-safe.
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
        set +e
        ${lib.getExe' pkgs.util-linux "script"} -qefc \
          "${ollama} pull $(printf '%q' "$model")" /dev/null 2>&1 \
          | LC_ALL=C ${lib.getExe' pkgs.coreutils "tr"} -cd '\011\012\015\040-\176' \
          | ${lib.getExe' pkgs.coreutils "tr"} '\r' '\n'
        status=''${PIPESTATUS[0]}
        set -e
        if [ "$status" -ne 0 ]; then
          exit "$status"
        fi
        echo "finished model: $model"
      done
    '';
  };
}
