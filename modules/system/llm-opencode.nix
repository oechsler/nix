# Standalone OpenCode feature options and shared server controls.

{ config, lib, ... }:

let
  modelSpec = import ../lib/opencode.nix { inherit lib; };
in
{
  options.features.llm.opencode = {
    enable = (lib.mkEnableOption "OpenCode AI coding agent") // {
      # OpenCode can use external providers without enabling local backends.
      default = config.features.dev.enable;
    };
    server = {
      enable = lib.mkEnableOption "the persistent OpenCode background server";
      remote = lib.mkEnableOption "OpenCode remote access through OpenTunnel";
    };
    defaultModel = lib.mkOption {
      type = lib.types.str;
      default = "openai/gpt-6-luna";
      description = "Default OpenCode model in provider/model format.";
    };
    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Additional OpenCode V2 settings, excluding generated model, providers, MCP servers, agents, LSP servers, and formatters.";
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
            package = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "OpenCode V2 provider package.";
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
      default = { };
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

  config = {
    users.users.${config.user.name}.linger = lib.mkIf config.features.llm.opencode.server.enable true;

    assertions = [
      {
        assertion = !config.features.llm.opencode.server.enable || config.features.llm.opencode.enable;
        message = "features.llm.opencode.server.enable requires features.llm.opencode.enable.";
      }
      {
        assertion =
          !config.features.llm.opencode.server.remote || config.features.llm.opencode.server.enable;
        message = "features.llm.opencode.server.remote requires features.llm.opencode.server.enable.";
      }
      {
        assertion =
          !(config.features.llm.opencode.provider ? "ollama-remote")
          || !config.features.llm.opencode.provider."ollama-remote".enable
          || config.features.llm.opencode.provider."ollama-remote".baseURL != null;
        message = "The OpenCode provider 'ollama-remote' requires a baseURL endpoint.";
      }
    ];
  };
}
