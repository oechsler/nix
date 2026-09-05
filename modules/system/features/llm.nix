# Local and remote large language model feature options.

{ lib, ... }:

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
  };
}
