# Development Tools Configuration
#
# This module is split into three parts:
#
# 1. CLI Tools (features.dev.enable = true)
#    - Languages: Go, Rust, Java, Bun (JavaScript/TypeScript)
#    - Rust toolchain: compiler, Cargo, rust-src, Clippy, Rustfmt
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
  config,
  pkgs,
  features,
  lib,
  ...
}:
let
  jetbrainsPackages = {
    inherit (pkgs.jetbrains)
      clion
      datagrip
      dataspell
      gateway
      goland
      mps
      phpstorm
      pycharm
      rider
      webstorm
      ;
    idea-oss = pkgs.jetbrains.idea-oss;
    idea-ultimate = pkgs.jetbrains.idea;
    rubymine = pkgs.jetbrains.ruby-mine;
    rustrover = pkgs.jetbrains.rust-rover;
  };
in
{
  #===========================
  # Configuration
  #===========================

  config = lib.mkMerge [
    # CLI Development Tools (always useful, even on servers)
    (lib.mkIf features.dev.enable {
      home = {
        packages = with pkgs; [
          # Development utilities
          cloc # Count lines of code

          # Languages & Compilers
          go
          rustc
          cargo
          clippy
          rustfmt
          rustPlatform.rustcSrc # Rust standard library sources
          clang # C compiler for native dependencies
          lld # LLVM linker for native dependencies
          jdk
          bun # Runtime, package manager, and bunx (npx replacement)
        ];

        # Keep user-installed Bun CLIs and caches in the home directory.
        sessionPath = [
          "${config.home.homeDirectory}/.bun/bin"
          "${config.home.homeDirectory}/.local/bin"
        ];
        sessionVariables = {
          BUN_INSTALL = "${config.home.homeDirectory}/.bun";
          RUST_SRC_PATH = "${pkgs.rustPlatform.rustcSrc}";
          CC = "clang";
          CXX = "clang++";
          AR = "llvm-ar";
          RANLIB = "llvm-ranlib";
          CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER = "clang";
          RUSTFLAGS = "-C link-arg=-fuse-ld=lld";
          LDFLAGS = "-fuse-ld=lld";
        };
      };
    })

    # Distrobox requires a container runtime and follows its feature toggle.
    (lib.mkIf (features.dev.enable && features.virtualisation.container.enable) {
      home.packages = [ pkgs.distrobox ];
    })

    # Homelab/Infrastructure Tools
    (lib.mkIf features.dev.enable {
      home.packages = with pkgs; [
        ansible # Infrastructure automation
        opentofu # Terraform alternative (open-source)
      ];
    })

    # GUI Development Tools (only for desktop)
    (lib.mkIf (features.dev.enable && features.desktop.enable && features.dev.jetbrains.enable) {
      home.packages =
        with pkgs;
        (
          lib.optionals features.dev.dbeaver.enable [
            dbeaver-bin # Database GUI
          ]
          ++ map (name: lib.getAttr name jetbrainsPackages) features.dev.jetbrains.entries
        );
    })
  ];
}
