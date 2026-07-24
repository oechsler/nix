# OpenCode Auto Router (Home-Manager / User-Level Podman Containers)
#
# Lifts the three OCI containers (Ollama, LiteLLM, auto-router) from
# system-level root Podman into user-level (rootless) Podman via
# systemd user services.  All containers run inside a shared pod so
# they can reach each other through localhost without --network=host
# (which is unavailable rootless).
#
# Enabled when features.development.enable = true.
{
  config,
  pkgs,
  lib,
  features,
  ...
}:
let
  # Local Ollama models used for request classification.
  # Ordered by preference: primary classifier first, fallbacks in order.
  routerModels = [
    "qwen3:8b"
    "llama3.2:3b"
  ];

  # Models to pull into Ollama on first start.
  ollamaModels = [
    "qwen3:8b"
    "llama3.2:3b"
  ];

  routerEnv = pkgs.python3.withPackages (ps: [
    ps.fastapi
    ps.httpx
    ps.uvicorn
  ]);

  routerApp = pkgs.runCommand "opencode-auto-router-app" { } ''
    mkdir -p $out/app
    cp ${../../programs/opencode-auto-router/router.py} $out/app/router.py
  '';

  routerImage = pkgs.dockerTools.buildLayeredImage {
    name = "opencode-auto-router";
    tag = "latest";
    contents = [
      routerEnv
      routerApp
    ];
    config = {
      Cmd = [
        "${routerEnv}/bin/uvicorn"
        "--app-dir"
        "${routerApp}/app"
        "router:app"
        "--host"
        "0.0.0.0"
        "--port"
        "4000"
      ];
      Env = [
        "PYTHONUNBUFFERED=1"
      ];
    };
  };

  litellmConfig = ../../programs/opencode-auto-router/litellm.yaml;

  podman = "${pkgs.podman}/bin/podman";

  mkPullScript = lib.concatMapStringsSep "\n" (model: ''
    until ${podman} exec opencode-ollama ollama list >/dev/null 2>&1; do
      sleep 2
    done
    ${podman} exec opencode-ollama ollama pull ${lib.escapeShellArg model}
  '') ollamaModels;

  routerModelsStr = lib.concatStringsSep "," routerModels;
in
{
  config = lib.mkIf features.development.enable {
    # -----------------------------------------------------------------
    # Secrets – SOPS (home‑manager level, same source file as system)
    # -----------------------------------------------------------------
    sops.secrets = {
      "opencode/mistral/api-key" = { };
      "opencode/opencode-go/api-key" = { };
    };

    sops.templates."opencode-auto-router-litellm.env" = {
      content = ''
        MISTRAL_API_KEY=${config.sops.placeholder."opencode/mistral/api-key"}
        OPENCODE_GO_API_KEY=${config.sops.placeholder."opencode/opencode-go/api-key"}
      '';
    };

    # -----------------------------------------------------------------
    # User systemd services
    # -----------------------------------------------------------------
    systemd.user.services = {
      # -- Pod ---------------------------------------------------------
      "opencode-auto-router-pod" = {
        Unit = {
          Description = "OpenCode shared pod (ollama + litellm + router)";
          After = [ "network-online.target" ];
        };
        Service = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${podman} pod create --name=opencode-auto -p 127.0.0.1:11434:11434 -p 127.0.0.1:8000:8000 -p 127.0.0.1:4000:4000";
          ExecStop = "-${podman} pod rm -f opencode-auto";
        };
        Install.WantedBy = [ "default.target" ];
      };

      # -- Ollama ------------------------------------------------------
      "podman-opencode-ollama" = {
        Unit = {
          Description = "OpenCode Ollama (user, rootless)";
          After = [ "opencode-auto-router-pod.service" ];
          Requires = [ "opencode-auto-router-pod.service" ];
          PartOf = [ "opencode-auto-router-pod.service" ];
        };
        Service = {
          ExecStartPre = "-${podman} rm -f opencode-ollama";
          ExecStart = lib.concatStringsSep " " [
            podman
            "run"
            "--name=opencode-ollama"
            "--rm"
            "--pod=opencode-auto"
            "--device=/dev/kfd"
            "--device=/dev/dri"
            "-v opencode-ollama:/root/.ollama"
            "-e OLLAMA_KEEP_ALIVE=30s"
            "docker.io/ollama/ollama:latest"
          ];
          ExecStop = "${podman} stop opencode-ollama";
          Restart = "on-failure";
          RestartSec = "5s";
        };
        Install.WantedBy = [ "default.target" ];
      };

      # -- LiteLLM -----------------------------------------------------
      "podman-opencode-litellm" = {
        Unit = {
          Description = "OpenCode LiteLLM (user, rootless)";
          After = [
            "opencode-auto-router-pod.service"
            "podman-opencode-ollama.service"
          ];
          Requires = [ "opencode-auto-router-pod.service" ];
          PartOf = [ "opencode-auto-router-pod.service" ];
        };
        Service = {
          ExecStartPre = "-${podman} rm -f opencode-litellm";
          ExecStart = lib.concatStringsSep " " [
            podman
            "run"
            "--name=opencode-litellm"
            "--rm"
            "--pod=opencode-auto"
            "-v ${litellmConfig}:/etc/litellm/config.yaml:ro"
            "--env-file=${config.sops.templates."opencode-auto-router-litellm.env".path}"
            "ghcr.io/berriai/litellm:main-latest"
            "--config /etc/litellm/config.yaml --host 0.0.0.0 --port 8000"
          ];
          ExecStop = "${podman} stop opencode-litellm";
          Restart = "on-failure";
          RestartSec = "5s";
        };
        Install.WantedBy = [ "default.target" ];
      };

      # -- Router image loader -----------------------------------------
      "opencode-auto-router-load-image" = {
        Unit = {
          Description = "Load opencode-auto-router image into user Podman storage";
          Before = [ "podman-opencode-auto-router.service" ];
        };
        Service = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${podman} load -i ${routerImage}";
          ExecStartPost = "-${podman} image prune -f";
        };
        Install.WantedBy = [ "default.target" ];
      };

      # -- Auto-router -------------------------------------------------
      "podman-opencode-auto-router" = {
        Unit = {
          Description = "OpenCode Auto Router (user, rootless)";
          After = [
            "opencode-auto-router-pod.service"
            "podman-opencode-litellm.service"
            "opencode-auto-router-load-image.service"
          ];
          Requires = [
            "opencode-auto-router-pod.service"
            "opencode-auto-router-load-image.service"
          ];
          PartOf = [ "opencode-auto-router-pod.service" ];
        };
        Service = {
          ExecStartPre = "-${podman} rm -f opencode-auto-router";
          ExecStart = lib.concatStringsSep " " [
            podman
            "run"
            "--name=opencode-auto-router"
            "--rm"
            "--pod=opencode-auto"
            "-v ${config.home.homeDirectory}/.local/share/opencode/auth.json:/var/lib/opencode/auth.json"
            "-e ROUTER_MODELS=${routerModelsStr}"
            "-e OLLAMA_URL=http://127.0.0.1:11434"
            "-e LITELLM_URL=http://127.0.0.1:8000/v1"
            "-e OPENCODE_AUTH_FILE=/var/lib/opencode/auth.json"
            "-e OPENAI_CHATGPT_MODEL=gpt-5.5"
            "-e DEFAULT_MODEL=deepseek-v4-pro"
            "opencode-auto-router:latest"
          ];
          ExecStop = "${podman} stop opencode-auto-router";
          Restart = "on-failure";
          RestartSec = "5s";
        };
        Install.WantedBy = [ "default.target" ];
      };

      # -- Pull Ollama models (oneshot) --------------------------------
      "opencode-auto-router-pull-models" = {
        Unit = {
          Description = "Pull Ollama models for classification";
          After = [ "podman-opencode-ollama.service" ];
          Requires = [ "podman-opencode-ollama.service" ];
        };
        Service = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = mkPullScript;
        };
        Install.WantedBy = [ "default.target" ];
      };
    };
  };
}
