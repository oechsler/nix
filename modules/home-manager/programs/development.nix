# Development Tools Configuration
#
# This module is split into three parts:
#
# 1. CLI Tools (features.development.enable = true)
#    - Languages: Go, Rust, Java, Node.js
#    - Utilities: cloc, distrobox
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
# Server mode disables development tools.

{
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

          # Languages & Compilers
          go
          rustup
          gcc # C compiler needed by cargo for native dependencies (linker)
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

     # Homelab/Infrastructure Tools
     (lib.mkIf features.development.enable {
       home.packages = with pkgs; [
         ansible # Infrastructure automation
         opentofu # Terraform alternative (open-source)
         pvetui # Proxmox VE Terminal UI
       ];
     })

    # GUI Development Tools (only for desktop)
    (lib.mkIf (features.development.enable && features.desktop.enable) {
      home.packages = with pkgs; [
        dbeaver-bin # Database GUI
        jetbrains.goland # Go IDE
        jetbrains.rust-rover # Rust IDE
      ];
    })
  ];
}
