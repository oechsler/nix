# OpenCode Auto Router Stack
#
# Runs Ollama, LiteLLM, and an OpenAI-compatible auto-router as OCI containers.
# OpenCode talks only to the auto provider; the router chooses local or cloud backends.

{
  config,
  lib,
  pkgs,
  ...
}:

let
  routerModel = "qwen3:8b";
  ollamaModels = [
    "qwen3:8b"
    "qwen3:14b"
    "qwen3:32b"
  ];

  routerEnv = pkgs.python3.withPackages (ps: [
    ps.fastapi
    ps.httpx
    ps.uvicorn
  ]);

  routerApp = pkgs.runCommand "opencode-auto-router-app" { } ''
    mkdir -p $out/app
    cp ${./opencode-auto-router/router.py} $out/app/router.py
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
in
{
  config = lib.mkIf config.features.development.enable {
    sops.secrets."opencode/mistral/api-key" = { };
    sops.secrets."opencode/opencode-go/api-key" = { };

    sops.templates."opencode-auto-router-litellm.env".content = ''
      MISTRAL_API_KEY=${config.sops.placeholder."opencode/mistral/api-key"}
      OPENCODE_GO_API_KEY=${config.sops.placeholder."opencode/opencode-go/api-key"}
    '';

    virtualisation.oci-containers.backend = "podman";

    virtualisation.oci-containers.containers = {
      opencode-ollama = {
        image = "docker.io/ollama/ollama:latest";
        autoStart = true;
        ports = [ "127.0.0.1:11434:11434" ];
        volumes = [
          "opencode-ollama:/root/.ollama"
        ];
        environment = {
          OLLAMA_KEEP_ALIVE = "30s";
        };
        extraOptions = [
          "--network=host"
          "--device=/dev/kfd"
          "--device=/dev/dri"
          "--group-add=video"
        ];
      };

      opencode-litellm = {
        image = "ghcr.io/berriai/litellm:main-latest";
        autoStart = true;
        cmd = [
          "--config"
          "/etc/litellm/config.yaml"
          "--host"
          "0.0.0.0"
          "--port"
          "8000"
        ];
        ports = [ "127.0.0.1:8000:8000" ];
        volumes = [
          "${./opencode-auto-router/litellm.yaml}:/etc/litellm/config.yaml:ro"
        ];
        environmentFiles = [ config.sops.templates."opencode-auto-router-litellm.env".path ];
        extraOptions = [ "--network=host" ];
        dependsOn = [ "opencode-ollama" ];
      };

      opencode-auto-router = {
        image = "opencode-auto-router:latest";
        imageFile = routerImage;
        autoStart = true;
        ports = [ "127.0.0.1:4000:4000" ];
        environment = {
          ROUTER_MODEL = routerModel;
          OLLAMA_URL = "http://127.0.0.1:11434";
          LITELLM_URL = "http://127.0.0.1:8000/v1";
          OPENCODE_AUTH_FILE = "/var/lib/opencode/auth.json";
          OPENAI_CHATGPT_MODEL = "gpt-5.5";
          DEFAULT_MODEL = "deepseek-v4-pro";
        };
        volumes = [
          "/home/${config.user.name}/.local/share/opencode/auth.json:/var/lib/opencode/auth.json"
        ];
        extraOptions = [ "--network=host" ];
        dependsOn = [
          "opencode-ollama"
          "opencode-litellm"
        ];
      };
    };

    systemd.services.opencode-auto-router-pull-models = {
      description = "Pull Ollama models for OpenCode auto-router";
      after = [ "podman-opencode-ollama.service" ];
      requires = [ "podman-opencode-ollama.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ config.virtualisation.podman.package ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = lib.concatMapStringsSep "\n" (model: ''
        until podman exec opencode-ollama ollama list >/dev/null 2>&1; do
          sleep 2
        done
        podman exec opencode-ollama ollama pull ${lib.escapeShellArg model}
      '') ollamaModels;
    };

  };
}
