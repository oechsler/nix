# OpenCode Model Helpers
#
# Shared model metadata types and conversion helpers for OpenCode providers.

{ lib }:

let
  reasoningDefaults = {
    low = 1024;
    medium = 2048;
    high = 4096;
    xhigh = 8192;
  };
  reasoningProfiles = lib.types.submodule {
    options = {
      budgets = lib.mkOption {
        type = lib.types.submodule {
          options = lib.mapAttrs (
            _profile: budget:
            lib.mkOption {
              type = lib.types.ints.unsigned;
              default = budget;
              description = "Maximum reasoning tokens for this canonical profile; this is a ceiling, not a target.";
            }
          ) reasoningDefaults;
        };
        default = { };
        description = "Model-specific reasoning token ceilings, overriding the generic profile defaults.";
      };
      nativeEffort = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Optional model-native reasoning effort by canonical profile; omitted means native default behavior.";
      };
      effortTransport = lib.mkOption {
        type = lib.types.enum [
          "none"
          "chat_template_kwargs"
          "top_level"
        ];
        default = "none";
        description = "Request transport for native effort, when the model has a verified effort selector.";
      };
      chatTemplateKwargs = lib.mkOption {
        type = lib.types.attrs;
        default = { };
        description = "Additional chat_template_kwargs sent with every reasoning profile request.";
      };
      chatTemplateKwargsByProfile = lib.mkOption {
        type = lib.types.attrsOf lib.types.attrs;
        default = { };
        description = "Additional chat_template_kwargs merged for individual canonical reasoning profiles.";
      };
    };
  };
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
    reasoningProfile = lib.mkOption {
      type = lib.types.nullOr reasoningProfiles;
      default = null;
      description = "Optional model-specific mapping of canonical reasoning profiles to budgets and native effort.";
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
  inherit reasoningDefaults reasoningProfiles;

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
    modelName: model:
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
      id = modelName;
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
