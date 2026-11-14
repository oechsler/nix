# Shared large language model feature and backend composition.

{ lib, ... }:

{
  imports = [
    ./llama-cpp.nix
    ./llm-opencode.nix
    ./ollama.nix
  ];

  options.features.llm.enable = (lib.mkEnableOption "large language model services") // {
    default = false;
  };
}
