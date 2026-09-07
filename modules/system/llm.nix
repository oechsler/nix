# Shared large language model feature and backend composition.

{ lib, ... }:

{
  imports = [
    ./llama-cpp.nix
    ./ollama.nix
  ];

  options.features.llm.enable = (lib.mkEnableOption "large language model services") // {
    default = false;
  };
}
