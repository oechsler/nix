# OpenCode Model Helpers
#
# Shared model metadata types and conversion helpers for OpenCode providers.

{ lib }:

{
  type = lib.types.submodule {
    options = {
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
    in
    {
      inherit (model) name;
    }
    // lib.optionalAttrs (toolCall != null) { tool_call = toolCall; }
    // lib.optionalAttrs (reasoning != null) { inherit reasoning; }
    // lib.optionalAttrs (temperature != null) { inherit temperature; }
    // lib.optionalAttrs (context != null || output != null) {
      limit =
        lib.optionalAttrs (context != null) { inherit context; }
        // lib.optionalAttrs (output != null) { inherit output; };
    };
}
