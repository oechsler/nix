# Declarative llama.cpp server with Nix-owned, hash-pinned GGUF artifacts.

{
  config,
  lib,
  pkgs,
  ...
}:

let
  modelSpec = import ../lib/opencode.nix { inherit lib; };
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
        ++ lib.optional (cfg.fitTarget != null) "fit-target = ${toString cfg.fitTarget}"
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
  ]
  ++ lib.optional (cfg.specType != "none") "--spec-type ${cfg.specType}"
  ++ lib.optional (cfg.specType != "none") "--spec-draft-n-max ${toString cfg.specDraftMax}"
  ++ lib.optional (cfg.specType != "none") "--spec-draft-p-min ${toString cfg.specDraftMinP}";
in
{
  options.features.llm.llamaCpp = {
    enable = (lib.mkEnableOption "llama.cpp local model server") // {
      default = false;
    };

    backend = lib.mkOption {
      type = lib.types.enum [
        "cpu"
        "vulkan"
        "rocm"
      ];
      default = if config.features.hardware.gpu == "amd" then "vulkan" else "cpu";
      description = "llama.cpp backend package: CPU, Vulkan, or ROCm. Vulkan is selected by default on AMD hosts and CPU otherwise.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default =
        {
          cpu = pkgs.llama-cpp;
          vulkan = pkgs.llama-cpp-vulkan;
          rocm = pkgs.llama-cpp-rocm;
        }
        .${config.features.llm.llamaCpp.backend};
      description = "llama.cpp package used by the service; normally selected automatically from backend, but available for advanced package overrides.";
    };

    server = lib.mkEnableOption "llama.cpp API access from other hosts";

    port = lib.mkOption {
      type = lib.types.ints.between 1 65535;
      default = 8080;
      description = "TCP port for the llama.cpp OpenAI-compatible API.";
    };

    context = lib.mkOption {
      type = lib.types.ints.positive;
      default = 32768;
      description = "Default prompt context length in tokens. Larger values use more memory; a model's context value overrides this default.";
    };

    output = lib.mkOption {
      type = lib.types.ints.positive;
      default = 16384;
      description = "Maximum generated tokens advertised to OpenCode.";
    };

    parallel = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = "Number of concurrent llama.cpp server slots. Higher values support more simultaneous requests but increase memory use.";
    };

    batchSize = lib.mkOption {
      type = lib.types.ints.positive;
      default = 2048;
      description = "Maximum logical batch size for prompt processing.";
    };

    microBatchSize = lib.mkOption {
      type = lib.types.ints.positive;
      default = 512;
      description = "Maximum physical batch size used while evaluating a batch.";
    };

    threads = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = "CPU threads used for generation, or null to use llama.cpp's automatic default.";
    };

    threadsBatch = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = "CPU threads used for prompt and batch processing, or null to follow the generation thread setting.";
    };

    flashAttention = lib.mkOption {
      type = lib.types.enum [
        "auto"
        "on"
        "off"
      ];
      default = "auto";
      description = "Flash Attention mode: auto, on, or off.";
    };

    gpuLayers = lib.mkOption {
      type = lib.types.either lib.types.ints.unsigned (
        lib.types.enum [
          "auto"
          "all"
        ]
      );
      default = "auto";
      description = "Maximum model layers to offload, as a non-negative layer count, auto, or all.";
    };

    fitTarget = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = "Memory margin in MiB reserved on each device while llama.cpp automatically fits GPU layers; null uses llama.cpp's default.";
    };

    device = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "Vulkan0";
      description = "Optional llama.cpp device name for an accelerated backend.";
    };

    cacheTypeK = lib.mkOption {
      type = lib.types.enum [
        "f32"
        "f16"
        "bf16"
        "q8_0"
        "q4_0"
        "q4_1"
        "iq4_nl"
        "q5_0"
        "q5_1"
      ];
      default = "f16";
      description = "KV-cache data type for K.";
    };

    cacheTypeV = lib.mkOption {
      type = lib.types.enum [
        "f32"
        "f16"
        "bf16"
        "q8_0"
        "q4_0"
        "q4_1"
        "iq4_nl"
        "q5_0"
        "q5_1"
      ];
      default = "f16";
      description = "KV-cache data type for V.";
    };

    modelsMax = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = "Maximum number of model instances that the router may keep loaded at once.";
    };

    modelsAutoload = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Automatically load a declared model when a request names it.";
    };

    jinja = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the model's Jinja chat template when supported.";
    };

    specType = lib.mkOption {
      type = lib.types.enum [
        "none"
        "draft-mtp"
      ];
      default = "none";
      description = "Speculative decoding implementation; draft-mtp requires a GGUF with a trained multi-token prediction head.";
    };

    specDraftMax = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3;
      description = "Maximum number of tokens proposed by the speculative decoding draft model.";
    };

    specDraftMinP = lib.mkOption {
      type = lib.types.addCheck lib.types.float (value: value >= 0.0 && value <= 1.0);
      default = 0.0;
      description = "Minimum draft-token probability for speculative decoding, from 0.0 to 1.0.";
    };

    models = lib.mkOption {
      type = lib.types.attrsOf modelSpec.llamaType;
      default = { };
      description = "Hash-pinned GGUF models indexed by an OpenCode model ID.";
    };
  };

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
