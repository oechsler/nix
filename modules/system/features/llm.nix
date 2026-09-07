# Local and remote large language model feature options.

{
  config,
  lib,
  pkgs,
  ...
}:

let
  modelSpec = import ../../lib/opencode.nix { inherit lib; };
in
{
  options.features.llm = {
    enable = (lib.mkEnableOption "large language model services") // {
      default = false;
    };

    ollama = {
      enable = (lib.mkEnableOption "Ollama local model server") // {
        # Ollama is the convenient backend when the parent feature is enabled;
        # hosts that only need llama.cpp can disable it explicitly.
        default = true;
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

    llamaCpp = {
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
        description = "Maximum logical batch size for prompt processing. Larger values may improve throughput but require more memory.";
      };

      microBatchSize = lib.mkOption {
        type = lib.types.ints.positive;
        default = 512;
        description = "Maximum physical batch size used while evaluating a batch. Larger values require more memory.";
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
        description = "Flash Attention mode: auto, on, or off. Auto lets llama.cpp choose based on the selected model and backend.";
      };

      gpuLayers = lib.mkOption {
        type = lib.types.either lib.types.ints.unsigned (
          lib.types.enum [
            "auto"
            "all"
          ]
        );
        default = "auto";
        description = "Maximum model layers to offload, as a non-negative layer count, auto, or all. Ignored by the CPU backend.";
      };

      device = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "Vulkan0";
        description = "Optional llama.cpp device name for an accelerated backend; null lets llama.cpp select a device automatically.";
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
        description = "KV-cache data type for K. Quantized types reduce memory use and may affect quality or performance.";
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
        description = "KV-cache data type for V. Quantized types reduce memory use and may affect quality or performance.";
      };

      modelsMax = lib.mkOption {
        type = lib.types.ints.positive;
        default = 1;
        description = "Maximum number of model instances that the router may keep loaded at once. Higher values increase memory use.";
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

      models = lib.mkOption {
        type = lib.types.attrsOf modelSpec.llamaType;
        default = { };
        description = "Hash-pinned GGUF models indexed by an OpenCode model ID containing only letters, numbers, '.', '_', ':' and '-'.";
      };
    };
  };
}
