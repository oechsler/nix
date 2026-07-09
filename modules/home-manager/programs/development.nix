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
      # API keys — decrypted by sops at boot, read by opencode via {file:...} syntax
      sops.secrets."opencode/mistral/api-key" = { };
      sops.secrets."opencode/openai/api-key" = { };

      programs.opencode = {
        enable = true;

        settings = {
          # Primary: Mistral (Codestral for code, Mistral Small for light tasks)
          # Budget: OpenCode Go (DeepSeek, no API key needed)
          # Fallback: OpenAI (ChatGPT Plus)
          enabled_providers = [
            "mistral"
            "opencode-go"
            "openai"
          ];

          model = "mistral/mistral-medium-latest";
          small_model = "mistral/mistral-small-latest";

          # Other models switchable via /models:
          #   opencode-go/deepseek-v4-pro
          #   openai/gpt-5.3-codex

          plugin = [
            "opencode-openai-codex-auth"
          ];

          provider = {
            opencode-go.options.timeout = 600000;
            mistral.options = {
              timeout = 600000;
              apiKey = "{file:${config.sops.secrets."opencode/mistral/api-key".path}}";
            };
            openai.options = {
              timeout = 600000;
              apiKey = "{file:${config.sops.secrets."opencode/openai/api-key".path}}";
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
