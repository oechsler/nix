{
  config,
  lib,
  pkgs,
  features,
  ...
}:

let
  cfg = config.programs.opencode-router;

  modelType = lib.types.submodule {
    options = {
      description = lib.mkOption {
        type = lib.types.str;
        description = "Model description for classification prompt";
      };
      family = lib.mkOption {
        type = lib.types.str;
        description = "Model family for escalation ladder";
      };
      provider = lib.mkOption {
        type = lib.types.enum [
          "litellm"
          "chatgpt"
          "ollama"
        ];
        default = "litellm";
        description = "Backend provider";
      };
      tier = lib.mkOption {
        type = lib.types.ints.between 1 10;
        default = 2;
        description = "Capability tier (1=trivial, 10=strongest)";
      };
      fallbacks = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Ordered fallback chain";
      };

      backend = lib.mkOption {
        type = lib.types.submodule {
          options = {
            litellm = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  model = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "LiteLLM model identifier";
                  };
                  apiBase = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "LiteLLM API base URL";
                  };
                  apiKeyEnv = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "Environment variable for API key";
                  };
                };
              };
              default = { };
            };
            chatgpt = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  model = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "ChatGPT model identifier";
                  };
                  serviceTier = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "Service tier for priority routing";
                  };
                };
              };
              default = { };
            };
          };
        };
        default = { };
      };

      hidden = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Hide from client model list";
      };
      displayName = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Human-readable display name";
      };
    };
  };
in
{
  imports = [
    ./router.nix
    ./litellm.nix
    ./client.nix
    ./services.nix
    ./secrets.nix
  ];

  options.programs.opencode-router = {
    enable = lib.mkEnableOption "OpenCode Auto Router";

    host = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Router bind address";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 4000;
      description = "Router bind port";
    };
    logLevel = lib.mkOption {
      type = lib.types.enum [
        "trace"
        "debug"
        "info"
        "warn"
        "error"
      ];
      default = "info";
      description = "Log level";
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "opencode-router:latest";
      description = "OCI image for the auto-router";
    };

    imagePackage = lib.mkOption {
      type = lib.types.path;
      description = "Built OCI image derivation for podman load";
    };

    classifier = {
      backend = lib.mkOption {
        type = lib.types.enum [
          "local"
          "cloud"
        ];
        default = "local";
        description = "Classification backend";
      };
      model = lib.mkOption {
        type = lib.types.str;
        default = "qwen3:8b";
        description = "Local classifier model";
      };
      timeoutSeconds = lib.mkOption {
        type = lib.types.int;
        default = 8;
        description = "Classification timeout";
      };
      cacheTtlSeconds = lib.mkOption {
        type = lib.types.int;
        default = 300;
        description = "Classification cache TTL";
      };
    };

    models = lib.mkOption {
      type = lib.types.attrsOf modelType;
      default = { };
      description = "Model definitions - drives router, litellm, and client config";
    };

    families = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.ladder = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            description = "Escalation ladder from weakest to strongest";
          };
        }
      );
      default = { };
      description = "Model family escalation ladders";
    };

    aliases = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Map client-facing names to canonical model IDs";
    };

    defaults = {
      model = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Default model when classification fails";
      };
      globalFallbacks = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Safety net appended to every fallback chain";
      };
      metadataFallbackChain = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Cheap-only chain for title/summary generation";
      };
    };

    crossFamilyEscalation = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Cross-family escalation map";
    };

    prompts = {
      classification = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Classification prompt template";
      };
      guidance = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "General guidance text";
      };
      modelGuidance = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Per-model guidance lines";
      };
    };

    markers = {
      retry = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Retry detection patterns";
      };
      retryPatterns = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Retry detection regex patterns";
      };
      metadata = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Metadata request patterns";
      };
      coding = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Coding request patterns";
      };
    };

    bans = {
      authSeconds = lib.mkOption {
        type = lib.types.int;
        default = 600;
        description = "Ban duration on auth errors";
      };
      exhaustionSeconds = lib.mkOption {
        type = lib.types.int;
        default = 900;
        description = "Ban duration on quota exhaustion";
      };
      sessionQualitySeconds = lib.mkOption {
        type = lib.types.int;
        default = 600;
        description = "Ban duration on user rejection";
      };
    };

    performance = {
      successWeight = lib.mkOption {
        type = lib.types.float;
        default = 1.0;
        description = "Points per successful request";
      };
      failureWeight = lib.mkOption {
        type = lib.types.float;
        default = -2.0;
        description = "Points deducted per failure";
      };
      rewardThreshold = lib.mkOption {
        type = lib.types.int;
        default = 5;
        description = "Successes before priority";
      };
      decayFactor = lib.mkOption {
        type = lib.types.float;
        default = 0.95;
        description = "Score decay factor";
      };
      decayIntervalSeconds = lib.mkOption {
        type = lib.types.int;
        default = 300;
        description = "Decay interval";
      };
    };

    circuitBreaker = {
      baseCooldownSeconds = lib.mkOption {
        type = lib.types.int;
        default = 30;
        description = "Base cooldown";
      };
      maxCooldownSeconds = lib.mkOption {
        type = lib.types.int;
        default = 300;
        description = "Max cooldown";
      };
    };

    cache = {
      enabled = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable caching";
      };
      ttlSeconds = lib.mkOption {
        type = lib.types.int;
        default = 300;
        description = "Cache TTL";
      };
      pattern = {
        enabled = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Regex-based classification";
        };
      };
      exact = {
        enabled = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Exact message hash matching";
        };
      };
      similarity = {
        enabled = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "N-gram similarity matching";
        };
        threshold = lib.mkOption {
          type = lib.types.float;
          default = 0.85;
          description = "Similarity threshold";
        };
        maxEntries = lib.mkOption {
          type = lib.types.int;
          default = 1000;
          description = "LRU cache size";
        };
      };
      llm = {
        enabled = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "LLM classification cache";
        };
      };
    };

    agentInstruction = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Agent instruction text prepended to tool requests";
    };

    notice = {
      format = lib.mkOption {
        type = lib.types.str;
        default = "> **{display_name}**\n> {reason}";
        description = "Notice format";
      };
      redirectFormat = lib.mkOption {
        type = lib.types.str;
        default = "> **{original_display} → {display_name}**\n> {reason}";
        description = "Redirect notice format";
      };
    };

    displayNames = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Human-readable model names";
    };

    chatgpt = {
      tokenUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://auth.openai.com/oauth/token";
        description = "OAuth token URL";
      };
      clientId = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "OAuth client ID";
      };
      responsesUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://chatgpt.com/backend-api/codex/responses";
        description = "Responses API URL";
      };
      accountClaimUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://api.openai.com/auth";
        description = "Account claim URL";
      };
      authFile = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/opencode/auth.json";
        description = "Auth file path";
      };
    };

    ollamaModels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Models to pull into Ollama";
    };

    litellmApiKeys = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "API keys for LiteLLM providers (env-var-name → sops-secret-path)";
      example = {
        MISTRAL_API_KEY = "opencode/mistral/api-key";
        OPENCODE_GO_API_KEY = "opencode/opencode-go/api-key";
      };
    };

    directProviders = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional native OpenCode providers to enable beside local and the always-enabled OpenAI provider";
      example = [ "mistral" ];
    };

    routerConfigFile = lib.mkOption {
      type = lib.types.path;
      description = "Generated router.toml path";
    };

    litellmConfigFile = lib.mkOption {
      type = lib.types.path;
      description = "Generated litellm.yaml path";
    };
  };

  config =
    lib.mkIf (features.development.enable && features.development.opencode.enable && cfg.enable)
      {
        programs.opencode-router = lib.mkMerge [
          (lib.mkIf (cfg.classifier.backend == "local" && cfg.classifier.model != "") {
            ollamaModels = [ cfg.classifier.model ];
          })
        ];
      };
}
