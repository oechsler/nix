# Development tooling and editor feature options.

{ config, lib, ... }:

let
  modelSpec = import ../../lib/opencode-model.nix { inherit lib; };
in
{
  options.features.dev = {
    enable = (lib.mkEnableOption "development tools") // {
      default = true;
    };
    opencode = {
      enable = (lib.mkEnableOption "OpenCode AI coding agent") // {
        default = config.features.dev.enable;
      };
      defaultModel = lib.mkOption {
        type = lib.types.str;
        default = "openai/gpt-5.6-luna";
        description = "Default OpenCode model in provider/model format.";
      };
      ollama = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = config.features.dev.ollama.enable;
          description = "Enable the Ollama provider in OpenCode.";
        };
        baseURL = lib.mkOption {
          type = lib.types.str;
          default = "http://127.0.0.1:11434/v1";
          description = "OpenAI-compatible Ollama API URL.";
        };
        context = lib.mkOption {
          type = lib.types.ints.positive;
          default = config.features.dev.ollama.context;
          description = "Default context length advertised to OpenCode for Ollama models.";
        };
        output = lib.mkOption {
          type = lib.types.ints.positive;
          default = 16384;
          description = "Default output length advertised to OpenCode for Ollama models.";
        };
        apiKeySecret = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "SOPS secret containing the Ollama API token.";
        };
        apiKey = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Plaintext Ollama API key for trusted configurations.";
        };
        models = lib.mkOption {
          type = lib.types.attrsOf modelSpec.type;
          default = config.features.dev.ollama.models;
          description = "Models exposed by the OpenCode Ollama provider.";
        };
      };
      settings = lib.mkOption {
        type = lib.types.attrs;
        default = { };
        description = "Additional OpenCode settings, excluding generated model, provider, MCP, LSP, formatter, and server settings.";
      };
      lsp = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              enable = lib.mkEnableOption "this OpenCode LSP server" // {
                default = true;
              };
              command = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Command and arguments for the LSP server.";
              };
              extensions = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "File extensions handled by the LSP server.";
              };
              env = lib.mkOption {
                type = lib.types.attrsOf lib.types.str;
                default = { };
                description = "Environment variables for the LSP server.";
              };
              initialization = lib.mkOption {
                type = lib.types.attrs;
                default = { };
                description = "Initialization options for the LSP server.";
              };
            };
          }
        );
        default = { };
        description = "Additional OpenCode LSP servers and overrides.";
      };
      formatter = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              enable = lib.mkEnableOption "this OpenCode formatter" // {
                default = true;
              };
              command = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Command and arguments for the formatter.";
              };
              extensions = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "File extensions handled by the formatter.";
              };
              environment = lib.mkOption {
                type = lib.types.attrsOf lib.types.str;
                default = { };
                description = "Environment variables for the formatter.";
              };
            };
          }
        );
        default = { };
        description = "Additional OpenCode formatters and overrides.";
      };
      provider = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              enable = lib.mkEnableOption "this OpenCode provider" // {
                default = true;
              };
              name = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Provider display name.";
              };
              npm = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "AI SDK provider package.";
              };
              baseURL = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "OpenAI-compatible provider base URL.";
              };
              apiKeySecret = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "SOPS secret path for the provider API key.";
              };
              apiKey = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Plaintext provider API key for trusted configurations.";
              };
              models = lib.mkOption {
                type = lib.types.attrsOf modelSpec.type;
                default = { };
                description = "Models exposed by this provider.";
              };
            };
          }
        );
        default = {
          openai = {
            models = {
              "gpt-5.6-luna".name = "GPT-5.6 Luna";
              "gpt-5.6-terra".name = "GPT-5.6 Terra";
              "gpt-5.6-sol".name = "GPT-5.6 Sol";
            };
          };
          "opencode-go" = {
            name = "OpenCode Go";
            npm = "@ai-sdk/openai-compatible";
            baseURL = "https://opencode.ai/zen/go/v1";
            apiKeySecret = "opencode/provider/opencode-go/api-key";
            models = {
              "deepseek-v4-flash".name = "DeepSeek V4 Flash";
              "deepseek-v4-pro".name = "DeepSeek V4 Pro";
              "gpt-5.6-luna".name = "GPT-5.6 Luna";
              "qwen3.7-plus".name = "Qwen3.7 Plus";
              "qwen3.7-max".name = "Qwen3.7 Max";
              "qwen3.8-max".name = "Qwen3.8 Max";
            };
          };
        };
        description = "OpenCode model providers configured per host.";
      };
      mcp = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              enable = lib.mkEnableOption "this OpenCode MCP server" // {
                default = false;
              };
              type = lib.mkOption {
                type = lib.types.enum [
                  "local"
                  "remote"
                ];
                default = "remote";
                description = "MCP connection type.";
              };
              url = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Remote MCP server URL.";
              };
              command = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Command and arguments for a local MCP server.";
              };
              headers = lib.mkOption {
                type = lib.types.attrsOf lib.types.str;
                default = { };
                description = "Additional static MCP request headers.";
              };
              tokenSecret = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "SOPS secret path for a bearer token.";
              };
              token = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Plaintext bearer token for trusted configurations.";
              };
              tokenHeader = lib.mkOption {
                type = lib.types.str;
                default = "Authorization";
                description = "Header receiving the configured token.";
              };
              tokenPrefix = lib.mkOption {
                type = lib.types.str;
                default = "Bearer ";
                description = "Prefix prepended to the configured token.";
              };
              insecureTls = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Disable TLS certificate verification for this remote MCP (applies to the OpenCode process).";
              };
              oauth = lib.mkOption {
                type = lib.types.nullOr (
                  lib.types.submodule {
                    options = {
                      clientId = lib.mkOption {
                        type = lib.types.nullOr lib.types.str;
                        default = null;
                        description = "OAuth client ID.";
                      };
                      clientSecretSecret = lib.mkOption {
                        type = lib.types.nullOr lib.types.str;
                        default = null;
                        description = "SOPS secret path for the OAuth client secret.";
                      };
                      clientSecret = lib.mkOption {
                        type = lib.types.nullOr lib.types.str;
                        default = null;
                        description = "Plaintext OAuth client secret for trusted configurations.";
                      };
                      scope = lib.mkOption {
                        type = lib.types.nullOr lib.types.str;
                        default = null;
                        description = "OAuth scopes to request.";
                      };
                      callbackPort = lib.mkOption {
                        type = lib.types.nullOr (lib.types.ints.between 1 65535);
                        default = null;
                        description = "Local OAuth callback port.";
                      };
                      redirectUri = lib.mkOption {
                        type = lib.types.nullOr lib.types.str;
                        default = null;
                        description = "OAuth redirect URI.";
                      };
                    };
                  }
                );
                default = null;
                description = "OAuth/OIDC configuration for a remote MCP server.";
              };
              timeout = lib.mkOption {
                type = lib.types.ints.positive;
                default = 30000;
                description = "MCP request timeout in milliseconds.";
              };
            };
          }
        );
        default = { };
        description = "OpenCode MCP servers configured per host.";
      };
    };
    jetbrains = {
      enable = (lib.mkEnableOption "JetBrains IDEs") // {
        default = config.features.dev.enable;
      };
      entries = lib.mkOption {
        type = lib.types.listOf (
          lib.types.enum [
            "android-studio"
            "clion"
            "datagrip"
            "dataspell"
            "gateway"
            "goland"
            "idea-oss"
            "idea-ultimate"
            "mps"
            "phpstorm"
            "pycharm"
            "rider"
            "rubymine"
            "rustrover"
            "webstorm"
          ]
        );
        default = [
          "goland"
          "rustrover"
        ];
        description = "JetBrains IDEs to install.";
      };
    };
    android = {
      enable = (lib.mkEnableOption "Android development tooling") // {
        default = false;
      };
    };
    dbeaver = {
      enable = (lib.mkEnableOption "DBeaver database GUI") // {
        default = config.features.dev.enable;
      };
    };
  };
}
