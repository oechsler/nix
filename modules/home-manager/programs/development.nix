# Development Tools Configuration
#
# This module is split into two parts:
#
# 1. CLI Tools (features.development.enable = true)
#    - Languages: Go, Rust, Java, Node.js
#    - Kubernetes: kubectl, helm, k9s
#    - Utilities: cloc, distrobox
#    - Useful on servers and desktops
#
# 2. GUI Tools (features.development.gui.enable = true)
#    - VS Code
#    - JetBrains Toolbox (IntelliJ IDEA, etc.)
#    - DBeaver (Database GUI)
#    - Claude Code
#    - Only useful on desktops
#
# Server mode automatically disables GUI tools but keeps CLI tools.

{ config, pkgs, features, lib, ... }:

{
  config = lib.mkMerge [
    # CLI Development Tools (always useful, even on servers)
    (lib.mkIf features.development.enable {
      # Kubernetes config from sops
      sops = {
        defaultSopsFile = ../../../sops/sops.encrypted.yaml;
        age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";

        secrets."kubernetes/kubeconfig" = {
          path = "${config.home.homeDirectory}/.kube/config";
          mode = "0600";  # kubectl/kubectx need read+write permissions
        };
      };

      home.file.".kube/.keep".text = "";

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

        # Development utilities
        cloc          # Count lines of code
        distrobox     # Container environments

        # Languages & Compilers
        go
        rustup
        jdk
        nodejs
      ];
    })

    # GUI Development Tools (only for desktop)
    (lib.mkIf (features.development.enable && features.development.gui.enable) {
      home.packages = with pkgs; [
        dbeaver-bin        # Database GUI
        jetbrains-toolbox  # IntelliJ IDEA, etc.
        claude-code        # AI-powered editor
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
