# Development Tools Configuration
#
# This module is split into three parts:
#
# 1. CLI Tools (features.development.enable = true)
#    - Languages: Go, Rust, Java, Node.js
#    - Utilities: cloc, distrobox
#    - opencode (AI coding agent)
#    - Useful on servers and desktops
#
# 2. Kubernetes Tools (features.development.kubernetes.enable = true)
#    - kubectl, helm, k9s
#
# 3. GUI Tools (features.development.gui.enable = true)
#    - VS Code
#    - JetBrains Toolbox (IntelliJ IDEA, etc.)
#    - DBeaver (Database GUI)
#    - Only useful on desktops
#
# Server mode automatically disables GUI tools but keeps CLI tools.

{ pkgs, features, lib, ... }:

{
  #===========================
  # Configuration
  #===========================

  config = lib.mkMerge [
    # CLI Development Tools (always useful, even on servers)
    (lib.mkIf features.development.enable {
      home.packages = with pkgs; [
        # Development utilities
        cloc          # Count lines of code
        distrobox     # Container environments
        ansible       # Infrastructure automation
        opentofu      # Terraform alternative (open-source)

        # Languages & Compilers
        go
        rustup
        jdk
        nodejs
      ];
    })

    # Kubernetes Tools (optional)
    (lib.mkIf (features.development.enable && features.development.kubernetes.enable) {
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
        kubeseal    # Sealed Secrets CLI
        kubelogin-oidc  # kubectl OIDC login plugin (int128/kubelogin)
      ];
    })

    # CLI AI Tools (useful on servers and desktops)
    (lib.mkIf features.development.enable {
      home.packages = with pkgs; [ claude-code ];

      programs.opencode = {
        enable = true;

        settings = {
          # Nur Go (Sparpreis) + OpenAI/Anthropic direkt (Notnagel)
          enabled_providers = [ "opencode-go" "openai" "anthropic" ];

          model = "opencode-go/deepseek-v4-pro";
          small_model = "opencode-go/deepseek-v4-flash";

          # Notnagel (per /models umschaltbar):
          #   openai/gpt-5.3-codex      (ChatGPT Plus/Pro)
          #   anthropic/claude-haiku-4-6  (Claude Code Auth)
          #   anthropic/claude-sonnet-4-6 (Claude Code Auth)

          plugin = [
            "opencode-claude-auth"
            "opencode-openai-codex-auth"
          ];

          provider = {
            opencode-go.options.timeout = 600000;
            openai.options.timeout = 600000;
            anthropic.options.timeout = 600000;
          };
        };
      };
    })

    # GUI Development Tools (only for desktop)
    (lib.mkIf (features.development.enable && features.development.gui.enable) {
      home.packages = with pkgs; [
        dbeaver-bin        # Database GUI
        jetbrains.goland   # Go IDE
      ];

      programs.vscode = {
        enable = true;
        package = pkgs.vscode;

        profiles.default = {
          userSettings = {
            "workbench.startupEditor" = "none";
          };

          extensions = with pkgs.vscode-extensions; [
            jnoortheen.nix-ide
            vscodevim.vim
          ];
        };
      };
    })
  ];
}
