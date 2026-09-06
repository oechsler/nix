# Declarative llama.cpp Vulkan server and hash-pinned GGUF model index.

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.features.llm.llamaCpp;
  enabled = config.features.llm.enable && cfg.enable;
  inherit (cfg) package;
  llamaServer = "${package}/bin/llama-server";
  modelDir = "/var/lib/llama.cpp/models";
  modelFiles = lib.mapAttrs (
    modelId: model:
    pkgs.fetchurl {
      name = "${modelId}.gguf";
      url = "https://huggingface.co/${model.source.repo}/resolve/${model.source.revision}/${model.source.file}?download=true";
      sha256 = model.source.sha256;
    }
  ) cfg.models;
  declaredIds = lib.escapeShellArgs (builtins.attrNames cfg.models);
  syncModels = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      modelId: model:
      let
        expected = model.source.sha256;
        modelPath = lib.escapeShellArg modelFiles.${modelId};
        linkPath = lib.escapeShellArg "${modelDir}/${modelId}.gguf";
      in
      ''
        expected="${expected}"
        actual="$(${pkgs.coreutils}/bin/sha256sum ${modelPath} | ${pkgs.coreutils}/bin/cut -d ' ' -f1)"
        if [ "$actual" != "$expected" ]; then
          echo "llama.cpp model hash mismatch for ${modelId}: expected $expected, got $actual" >&2
          exit 1
        fi
        ${pkgs.coreutils}/bin/rm -f ${linkPath}.new
        ln -s ${modelPath} ${linkPath}.new
        ${pkgs.coreutils}/bin/mv -Tf ${linkPath}.new ${linkPath}
      ''
    ) cfg.models
  );
  removeUndeclared = ''
    shopt -s nullglob
    for path in ${modelDir}/*.gguf; do
      name="''${path##*/}"
      case " ${declaredIds} " in
        *" ''${name%.gguf} "*) ;;
        *) echo "removing undeclared llama.cpp model: $name"; ${pkgs.coreutils}/bin/rm -f -- "$path" ;;
      esac
    done
  '';
in
{
  config = lib.mkIf enabled {
    assertions = [
      {
        assertion = cfg.models != { };
        message = "features.llm.llamaCpp.models must contain at least one hash-pinned model.";
      }
      {
        assertion = lib.all (modelId: builtins.match "[A-Za-z0-9][A-Za-z0-9._:-]*" modelId != null) (
          builtins.attrNames cfg.models
        );
        message = "features.llm.llamaCpp.models keys must start with a letter or number and contain only letters, numbers, '.', '_', ':' or '-'.";
      }
    ];

    environment.systemPackages = [ package ];

    users.groups.llama-cpp = { };
    users.users.llama-cpp = {
      isSystemUser = true;
      group = "llama-cpp";
      extraGroups = [
        "render"
        "video"
      ];
      description = "llama.cpp inference service";
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.server [ cfg.port ];

    systemd.services.llama-cpp-model-loader = {
      description = "Synchronize declarative llama.cpp models";
      before = [ "llama-cpp.service" ];
      wantedBy = [ "llama-cpp.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "llama-cpp";
        Group = "llama-cpp";
        StateDirectory = "llama.cpp";
      };
      script = ''
        set -euo pipefail
        ${pkgs.coreutils}/bin/mkdir -p ${modelDir}
        ${removeUndeclared}
        ${syncModels}
        echo "llama.cpp model index synchronized"
      '';
    };

    systemd.services.llama-cpp = {
      description = "llama.cpp OpenAI-compatible Vulkan server";
      wantedBy = [ "multi-user.target" ];
      requires = [ "llama-cpp-model-loader.service" ];
      after = [
        "network-online.target"
        "llama-cpp-model-loader.service"
      ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        ExecStart = lib.concatStringsSep " " [
          llamaServer
          "--models-dir ${modelDir}"
          "--models-max 1"
          "--models-autoload"
          "--host ${if cfg.server then "0.0.0.0" else "127.0.0.1"}"
          "--port ${toString cfg.port}"
          "--ctx-size ${toString cfg.context}"
          "--parallel 1"
          "--jinja"
          "--flash-attn on"
          "--device Vulkan0"
          "-ngl 999"
        ];
        User = "llama-cpp";
        Group = "llama-cpp";
        SupplementaryGroups = [
          "render"
          "video"
        ];
        Restart = "on-failure";
        RestartSec = 5;
        StateDirectory = "llama.cpp";
        LimitNOFILE = 65536;
      };
      environment = {
        GGML_BACKEND_PATH = "${package}/bin/libggml-vulkan.so";
        HOME = "/var/lib/llama.cpp";
      };
    };
  };
}
