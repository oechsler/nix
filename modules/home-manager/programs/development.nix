# Development Tools Configuration
#
# This module is split into three parts:
#
# 1. CLI Tools (features.development.enable = true)
#    - Languages: Go, Rust, Java, Node.js
#    - Utilities: cloc, distrobox
#    - opencode (AI coding agent) with API keys from SOPS
#    - Useful on development machines
#
# 2. Kubernetes Tools (features.development.enable = true)
#    - kubectl, helm, k9s
#
# 3. GUI Tools (features.development.enable && features.desktop.enable)
#    - JetBrains GoLand
#    - DBeaver (Database GUI)
#    - Only useful on desktops
#
# opencode API keys are stored as SOPS secrets:
#   opencode/mistral/api-key
#   opencode/openai/api-key
# opencode reads them via {file:/run/secrets/...} at runtime — no env vars needed.
#
# Server mode disables development tools.

{
  config,
  pkgs,
  features,
  lib,
  ...
}:

{
  #===========================
  # Configuration
  #===========================

  config = lib.mkMerge [
    # CLI Development Tools (always useful, even on servers)
    (lib.mkIf features.development.enable {
      home.packages = with pkgs; [
        # Development utilities
        cloc # Count lines of code
        distrobox # Container environments
        ansible # Infrastructure automation
        opentofu # Terraform alternative (open-source)

        # Languages & Compilers
        go
        rustup
        jdk
        nodejs
      ];
    })

    # Kubernetes Tools
    (lib.mkIf features.development.enable {
      catppuccin.k9s.transparent = true;

      programs.k9s = {
        enable = true;
        settings.k9s.ui = {
          enableMouse = true;
          logoless = true;
          splashless = true;
          reactive = true;
        };
      };

      home.packages = with pkgs; [
        # Kubernetes tools
        kubectl
        kubernetes-helm
        kubectx
        kubeseal # Sealed Secrets CLI
        kubelogin-oidc # kubectl OIDC login plugin (int128/kubelogin)
      ];
    })

    # CLI AI Tools (useful on servers and desktops)
    (lib.mkIf features.development.enable {
      # openai uses built-in OAuth — no API key needed
      programs.opencode = {
        enable = true;

        settings = {
          # The local provider routes everything through the auto-router.
          # openai is enabled solely for `opencode auth login --provider openai`;
          # all model selection should use local/* (auto-router) exclusively.
          enabled_providers = [
            "local"
            "openai"
          ];

          model = "local/auto";
          small_model = "local/auto";

          agent = {
            build.model = "local/auto";
            general.model = "local/auto";
            explore.model = "local/auto";
            plan.model = "local/auto";
            title.model = "local/mistral-small";
            summary.model = "local/mistral-small";
          };

          # Other models switchable via /models are all exposed by local/*.

          provider = {
            local = {
              npm = "@ai-sdk/openai-compatible";
              name = "Local";
                options = {
                  baseURL = "http://127.0.0.1:4000/v1";
                  apiKey = "dummy";
                  timeout = 600000;
                };
                models = {
                 auto = {
                   name = "Auto";
                   tool_call = true;
                   temperature = true;
                   limit = {
                     context = 128000;
                     output = 32768;
                   };
                 };
                 mistral-small = {
                   name = "Mistral Small";
                   tool_call = true;
                   temperature = true;
                   limit = {
                     context = 128000;
                     output = 32768;
                   };
                 };
                 mistral-medium = {
                   name = "Mistral Medium";
                   tool_call = true;
                   temperature = true;
                   limit = {
                     context = 128000;
                     output = 32768;
                   };
                 };
                  deepseek-v4-pro = {
                    name = "DeepSeek V4 Pro";
                    tool_call = true;
                    temperature = true;
                    limit = {
                      context = 128000;
                      output = 32768;
                    };
                  };
                  deepseek-v4-flash = {
                    name = "DeepSeek V4 Flash";
                    tool_call = true;
                    temperature = true;
                    limit = {
                      context = 128000;
                      output = 32768;
                    };
                  };
                  "qwen3.7-max" = {
                    name = "Qwen3.7 Max";
                    tool_call = true;
                    temperature = true;
                    limit = {
                      context = 128000;
                      output = 32768;
                    };
                  };
                  "qwen3.7-plus" = {
                    name = "Qwen3.7 Plus";
                    tool_call = true;
                    temperature = true;
                    limit = {
                      context = 128000;
                      output = 32768;
                    };
                  };
                  "qwen3.6-plus" = {
                    name = "Qwen3.6 Plus";
                    tool_call = true;
                    temperature = true;
                    limit = {
                      context = 128000;
                      output = 32768;
                    };
                  };
                   openai-luna-fast = {
                     name = "ChatGPT 5.6 Luna Fast";
                     tool_call = true;
                     temperature = true;
                     limit = {
                       context = 128000;
                       output = 32768;
                     };
                   };
                   openai-luna = {
                     name = "ChatGPT 5.6 Luna";
                     tool_call = true;
                     temperature = true;
                     limit = {
                       context = 128000;
                       output = 32768;
                     };
                   };
                   openai-sol-fast = {
                     name = "ChatGPT 5.6 Sol Fast";
                     tool_call = true;
                     temperature = true;
                     limit = {
                       context = 128000;
                       output = 32768;
                     };
                   };
                   openai-sol = {
                     name = "ChatGPT 5.6 Sol";
                     tool_call = true;
                     temperature = true;
                     limit = {
                       context = 128000;
                       output = 32768;
                     };
                   };
                   openai-terra-fast = {
                     name = "ChatGPT 5.6 Terra Fast";
                     tool_call = true;
                     temperature = true;
                     limit = {
                       context = 128000;
                       output = 32768;
                     };
                   };
                   openai-terra = {
                     name = "ChatGPT 5.6 Terra";
                     tool_call = true;
                     temperature = true;
                     limit = {
                       context = 128000;
                       output = 32768;
                     };
                   };
                   "qwen3:8b" = {
                     name = "Qwen3 8B (Local)";
                     tool_call = true;
                     temperature = true;
                     limit = {
                       context = 128000;
                       output = 32768;
                     };
                   };
                };
            };
          };
        };
      };
    })

    # GUI Development Tools (only for desktop)
    (lib.mkIf (features.development.enable && features.desktop.enable) {
      home.packages = with pkgs; [
        dbeaver-bin # Database GUI
        jetbrains.goland # Go IDE
      ];
    })
  ];
}
