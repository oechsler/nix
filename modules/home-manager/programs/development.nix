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
      # openai uses OAuth (opencode-openai-codex-auth plugin) — no API key needed
      programs.opencode = {
        enable = true;

        settings = {
          # OpenCode only exposes this local provider. It can still route to
          # local Ollama models, Mistral, or ChatGPT through the auto-router.
          enabled_providers = [
            "local"
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

          plugin = [
            "opencode-openai-codex-auth"
          ];

          provider = {
            local = {
              npm = "@ai-sdk/openai-compatible";
              name = "Local";
              options = {
                baseURL = "http://127.0.0.1:4000/v1";
                apiKey = "dummy";
                timeout = 600000;
              };
              models.auto = {
                name = "Auto";
                tool_call = true;
                temperature = true;
                limit = {
                  context = 128000;
                  output = 32768;
                };
              };
              models.mistral-small = {
                name = "Mistral Small";
                tool_call = true;
                temperature = true;
                limit = {
                  context = 128000;
                  output = 32768;
                };
              };
              models.mistral-medium = {
                name = "Mistral Medium";
                tool_call = true;
                temperature = true;
                limit = {
                  context = 128000;
                  output = 32768;
                };
              };
              models.deepseek-v4-pro = {
                name = "DeepSeek V4 Pro";
                tool_call = true;
                temperature = true;
                limit = {
                  context = 128000;
                  output = 32768;
                };
              };
              models.openai-chatgpt = {
                name = "ChatGPT 5.5";
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
