# Development Tools Configuration
#
# This module is split into three parts:
#
# 1. CLI Tools (features.dev.enable = true)
#    - Languages: Go, Rust, Java, Node.js
#    - Utilities: cloc, distrobox
#    - Useful on development machines
#
# 2. Homelab/Infrastructure Tools (features.dev.enable = true)
#    - ansible, opentofu
#
# 3. GUI Tools (features.dev.enable && features.desktop.enable)
#    - JetBrains GoLand
#    - DBeaver (Database GUI)
#    - Only useful on desktops
#
# Note: Kubernetes tools (kubectl, helm, k9s) are configured in kubernetes.nix
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
    (lib.mkIf features.dev.enable {
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

    # Homelab/Infrastructure Tools
    (lib.mkIf features.dev.enable {
      home.packages = with pkgs; [
        ansible # Infrastructure automation
        opentofu # Terraform alternative (open-source)
      ];
    })

    # GUI Development Tools (only for desktop)
    (lib.mkIf (features.dev.enable && features.desktop.enable) {
      home.packages =
        with pkgs;
        (
          lib.optionals features.dev.dbeaver.enable [
            dbeaver-bin # Database GUI
          ]
          ++ lib.optionals features.dev.jetbrains.enable [
            jetbrains.goland # Go IDE
            jetbrains.rust-rover # Rust IDE
          ]
        );
    })
  ];
}
