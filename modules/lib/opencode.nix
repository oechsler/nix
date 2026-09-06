# OpenCode Model Helpers
#
# Shared model metadata types and conversion helpers for OpenCode providers.

{ lib }:

let
  modelOptions = {
    name = lib.mkOption {
      type = lib.types.str;
      description = "Model display name.";
    };
    toolCall = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      description = "Whether the model supports native tool calls.";
    };
    reasoning = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      description = "Whether the model emits reasoning content.";
    };
    temperature = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      description = "Whether the model supports temperature control.";
    };
    context = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = "Maximum context length in tokens.";
    };
    output = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = "Maximum output length in tokens.";
    };
    input = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = "Maximum input length in tokens.";
    };
  };
in
{
  inherit modelOptions;

  type = lib.types.submodule {
    options = modelOptions;
  };

  llamaType = lib.types.submodule {
    options = modelOptions // {
      source = lib.mkOption {
        type = lib.types.submodule {
          options = {
            repo = lib.mkOption {
              type = lib.types.str;
              description = "Hugging Face repository containing the GGUF file.";
            };
            file = lib.mkOption {
              type = lib.types.str;
              description = "GGUF filename in the repository.";
            };
            revision = lib.mkOption {
              type = lib.types.str;
              default = "main";
              description = "Hugging Face branch, tag, or commit.";
            };
            sha256 = lib.mkOption {
              type = lib.types.strMatching "[0-9a-fA-F]{64}";
              description = "Expected SHA256 of the GGUF file.";
            };
          };
        };
        description = "Hash-pinned declarative GGUF source.";
      };
    };
  };

  toOpenCode =
    model:
    let
      toolCall = model.toolCall or null;
      reasoning = model.reasoning or null;
      temperature = model.temperature or null;
      context = model.context or null;
      output = model.output or null;
      input = model.input or null;
    in
    {
      inherit (model) name;
    }
    // lib.optionalAttrs (toolCall != null) { tool_call = toolCall; }
    // lib.optionalAttrs (reasoning != null) { inherit reasoning; }
    // lib.optionalAttrs (temperature != null) { inherit temperature; }
    // lib.optionalAttrs (context != null && output != null) {
      limit = {
        inherit context output;
      }
      // lib.optionalAttrs (input != null) { inherit input; };
    };
}
