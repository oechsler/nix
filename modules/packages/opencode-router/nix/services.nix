{
  config,
  lib,
  pkgs,
  features,
  ...
}:

let
  cfg = config.programs.opencode-router;

  podman = "${pkgs.podman}/bin/podman";

  desiredModels = cfg.ollamaModels;
  desiredModelsStr = lib.concatStringsSep " " (map lib.escapeShellArg desiredModels);

  syncScript = pkgs.writeShellScriptBin "opencode-router-sync-models" ''
    set -e
    echo "[opencode-router] Waiting for ollama container..."
    for i in $(seq 1 30); do
      if ${podman} exec opencode-ollama ollama list >/dev/null 2>&1; then
        break
      fi
      sleep 2
    done

    echo "[opencode-router] Pulling desired models..."
    for model in ${lib.concatStringsSep " " (map lib.escapeShellArg desiredModels)}; do
      ${podman} exec opencode-ollama ollama pull "$model"
    done

    echo "[opencode-router] Cleaning up models not in config..."
    ${podman} exec opencode-ollama ollama list \
      | tail -n +2 \
      | awk '{print $1}' \
      | while IFS= read -r m; do
          case " ${desiredModelsStr} " in
            *" $m "*) ;;
            *)
              echo "[opencode-router] Removing stale model: $m"
              ${podman} exec opencode-ollama ollama rm "$m"
              ;;
          esac
        done
    echo "[opencode-router] Models synced."
  '';

  useLocalClassifier = cfg.classifier.backend == "local";
in
{
  config =
    lib.mkIf (features.development.enable && features.development.opencode.enable && cfg.enable)
      {
        systemd.user.services = lib.mkMerge [
          {
            "opencode-router-pod" = {
              Unit = {
                Description = "OpenCode shared pod (LiteLLM + router, optionally Ollama)";
                After = [ "network-online.target" ];
                Wants = [
                  "podman-opencode-litellm.service"
                  "podman-opencode-router.service"
                ]
                ++ lib.optionals useLocalClassifier [
                  "podman-opencode-ollama.service"
                  "opencode-router-sync-models.service"
                ];
              };
              Service = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStartPre = "-${podman} pod rm -f opencode-router";
                ExecStart = "${podman} pod create --name=opencode-router -p 127.0.0.1:11434:11434 -p 127.0.0.1:8000:8000 -p 127.0.0.1:4000:4000";
                ExecStop = "-${podman} pod rm -f opencode-router";
                TimeoutStartSec = 30;
              };
              Install.WantedBy = [ "default.target" ];
            };

            "opencode-router-load-image" = {
              Unit = {
                Description = "Load opencode-router image into user Podman storage";
                Before = [ "podman-opencode-router.service" ];
              };
              Service = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = "${podman} load -i ${cfg.imagePackage}";
                ExecStartPost = "-${podman} image prune -f";
                TimeoutStartSec = 120;
              };
              Install.WantedBy = [ "default.target" ];
            };

            "podman-opencode-router" = {
              Unit = {
                Description = "OpenCode Auto Router (Rust, user, rootless)";
                After = [
                  "opencode-router-pod.service"
                  "podman-opencode-litellm.service"
                  "opencode-router-load-image.service"
                ]
                ++ lib.optionals useLocalClassifier [
                  "opencode-router-sync-models.service"
                ];
                Requires = [ "opencode-router-pod.service" ];
                Wants = [
                  "opencode-router-load-image.service"
                ]
                ++ lib.optionals useLocalClassifier [
                  "opencode-router-sync-models.service"
                ];
                PartOf = [ "opencode-router-pod.service" ];
              };
              Service = {
                ExecStartPre = [
                  "${podman} load -i ${cfg.imagePackage}"
                  "-${podman} rm -f opencode-router"
                ];
                ExecStart = lib.concatStringsSep " " [
                  podman
                  "run"
                  "--name=opencode-router"
                  "--rm"
                  "--pod=opencode-router"
                  "-v ${cfg.routerConfigFile}:/etc/opencode-router/config.toml:ro"
                  "-v ${config.home.homeDirectory}/.local/share/opencode/auth.json:/var/lib/opencode/auth.json:ro"
                  "opencode-router:latest"
                ];
                ExecStop = "${podman} stop opencode-router";
                Restart = "on-failure";
                RestartSec = "5s";
                TimeoutStartSec = 120;
              };
              Install.WantedBy = [ "default.target" ];
            };

            "podman-opencode-litellm" = {
              Unit = {
                Description = "OpenCode LiteLLM (user, rootless)";
                After = [ "opencode-router-pod.service" ];
                Requires = [ "opencode-router-pod.service" ];
                PartOf = [ "opencode-router-pod.service" ];
              };
              Service = {
                ExecStartPre = "-${podman} rm -f opencode-litellm";
                ExecStart = lib.concatStringsSep " " [
                  podman
                  "run"
                  "--name=opencode-litellm"
                  "--rm"
                  "--pod=opencode-router"
                  "-v ${cfg.litellmConfigFile}:/etc/litellm/config.yaml:ro"
                  "--env-file=${config.sops.templates."opencode-router-litellm.env".path}"
                  "ghcr.io/berriai/litellm:main-latest@sha256:be646214d7bc1cda0be57debbbf58e822ca4f233ddc50d0c0c7fa9b4a28063af"
                  "--config /etc/litellm/config.yaml --host 0.0.0.0 --port 8000"
                ];
                ExecStop = "${podman} stop opencode-litellm";
                Restart = "on-failure";
                RestartSec = "5s";
                TimeoutStartSec = 300;
              };
              Install.WantedBy = [ "default.target" ];
            };
          }
          (lib.mkIf useLocalClassifier {
            "podman-opencode-ollama" = {
              Unit = {
                Description = "OpenCode Ollama (user, rootless)";
                After = [ "opencode-router-pod.service" ];
                Requires = [ "opencode-router-pod.service" ];
                PartOf = [ "opencode-router-pod.service" ];
              };
              Service = {
                ExecStartPre = "-${podman} rm -f opencode-ollama";
                ExecStart = lib.concatStringsSep " " (
                  [
                    podman
                    "run"
                    "--name=opencode-ollama"
                    "--rm"
                    "--pod=opencode-router"
                    "--device=/dev/dri"
                  ]
                  ++ lib.optionals (features.hardware.gpu == "amd") [
                    "--device=/dev/kfd"
                  ]
                  ++ [
                    "-v opencode-ollama:/root/.ollama"
                    "-e OLLAMA_KEEP_ALIVE=5m"
                    "docker.io/ollama/ollama:0.32.5@sha256:4dea9fb511947e24a84237bb636b0203abcb2ff0d3fbc7b4ff865deb91362131"
                  ]
                );
                ExecStop = "${podman} stop opencode-ollama";
                Restart = "on-failure";
                RestartSec = "5s";
                TimeoutStartSec = 300;
              };
              Install.WantedBy = [ "default.target" ];
            };

            "opencode-router-sync-models" = {
              Unit = {
                Description = "Sync Ollama models for OpenCode auto-router";
                After = [ "podman-opencode-ollama.service" ];
                Requires = [ "podman-opencode-ollama.service" ];
              };
              Service = {
                Type = "oneshot";
                RemainAfterExit = true;
                TimeoutStartSec = 120;
                ExecStart = "${syncScript}/bin/opencode-router-sync-models";
              };
              Install.WantedBy = [ "default.target" ];
            };
          })
        ];
      };
}
