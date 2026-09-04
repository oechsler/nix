# Ollama local model server feature.

{ config, lib, ... }:

let
  cfg = config.features.dev.ollama;
in
{
  options.features.dev.ollama = {
    enable = (lib.mkEnableOption "Ollama local model server") // {
      default = false;
    };

    server = lib.mkEnableOption "Ollama API access from other hosts";

    models = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "gemma3:12b"
        "qwen3:8b"
      ];
      description = "Ollama models to pull declaratively after the server starts.";
    };
  };

  config = lib.mkIf (config.features.dev.enable && cfg.enable) {
    environment.systemPackages = [ config.services.ollama.package ];

    services.ollama = {
      enable = true;
      loadModels = cfg.models;
      host = if cfg.server then "0.0.0.0" else "127.0.0.1";
      openFirewall = cfg.server;
    };
  };
}
