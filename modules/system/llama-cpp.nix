# Declarative llama.cpp server with Nix-owned, hash-pinned GGUF artifacts.

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
  modelFiles = lib.mapAttrs (
    modelId: model:
    pkgs.fetchurl {
      name = "${modelId}.gguf";
      url = "https://huggingface.co/${model.source.repo}/resolve/${model.source.revision}/${model.source.file}?download=true";
      sha256 = model.source.sha256;
    }
  ) cfg.models;
  modelPreset = pkgs.writeText "llama-cpp-models.ini" (
    let
      modelSection =
        modelId:
        let
          model = cfg.models.${modelId};
        in
        [
          ""
          "[${modelId}]"
          "model = ${modelFiles.${modelId}}"
          "ctx-size = ${toString (if model.context == null then cfg.context else model.context)}"
          "parallel = ${toString cfg.parallel}"
          "batch-size = ${toString cfg.batchSize}"
          "ubatch-size = ${toString cfg.microBatchSize}"
          "flash-attn = ${cfg.flashAttention}"
          "cache-type-k = ${cfg.cacheTypeK}"
          "cache-type-v = ${cfg.cacheTypeV}"
          "n-gpu-layers = ${toString (if cfg.backend == "cpu" then "auto" else cfg.gpuLayers)}"
        ]
        ++ lib.optional (cfg.threads != null) "threads = ${toString cfg.threads}"
        ++ lib.optional (cfg.threadsBatch != null) "threads-batch = ${toString cfg.threadsBatch}"
        ++ lib.optional (cfg.device != null && cfg.backend != "cpu") "device = ${cfg.device}";
    in
    lib.concatStringsSep "\n" (
      [
        "version = 1"
        ""
        "[*]"
        "load-on-startup = ${if cfg.modelsAutoload then "true" else "false"}"
        "jinja = ${if cfg.jinja then "true" else "false"}"
      ]
      ++ lib.concatMap modelSection (builtins.attrNames cfg.models)
      ++ [ "" ]
    )
  );
  backendPath = {
    vulkan = "${package}/bin/libggml-vulkan.so";
    rocm = "${package}/bin/libggml-hip.so";
  };
  presetOptions = [
    "--models-preset ${modelPreset}"
    "--models-max ${toString cfg.modelsMax}"
    (if cfg.modelsAutoload then "--models-autoload" else "--no-models-autoload")
  ];
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
      {
        assertion = cfg.backend != "rocm" || config.features.hardware.gpu == "amd";
        message = "features.llm.llamaCpp.backend = \"rocm\" requires features.hardware.gpu = \"amd\".";
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

    systemd.services.llama-cpp = {
      description = "llama.cpp OpenAI-compatible server";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = lib.concatStringsSep " " (
          [
            "${package}/bin/llama-server"
            "--host ${if cfg.server then "0.0.0.0" else "127.0.0.1"}"
            "--port ${toString cfg.port}"
          ]
          ++ presetOptions
        );
        User = "llama-cpp";
        Group = "llama-cpp";
        SupplementaryGroups = [
          "render"
          "video"
        ];
        Restart = "on-failure";
        RestartSec = 5;
        LimitNOFILE = 65536;
      };
      # Split nixpkgs builds load accelerator backends dynamically. Point at the
      # selected backend library itself, not its containing directory.
      environment = lib.optionalAttrs (cfg.backend != "cpu") {
        GGML_BACKEND_PATH = backendPath.${cfg.backend};
      };
    };
  };
}
