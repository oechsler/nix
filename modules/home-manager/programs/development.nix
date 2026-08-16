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
  # RustRover expects the standard library below the toolchain directory.
  # Nix keeps rustc and rust-src in separate store paths, so provide the
  # conventional layout through stable Home-Manager-managed symlinks.
  rustToolchain = pkgs.runCommand "rust-toolchain" { } ''
    mkdir -p $out/bin $out/lib/rustlib/src
    ln -s ${pkgs.rustc}/bin/rustc $out/bin/rustc
    ln -s ${pkgs.cargo}/bin/cargo $out/bin/cargo
    ln -s ${pkgs.rustfmt}/bin/rustfmt $out/bin/rustfmt
    ln -s ${pkgs.rustPlatform.rustcSrc} $out/lib/rustlib/src/rust
  '';
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
          rustPlatform.rustcSrc # Sources used by rust-analyzer and rustc
          gcc # C compiler needed by cargo for native dependencies (linker)
          jdk
          bun # Runtime, package manager, and bunx (npx replacement)
        ];

        # Keep user-installed Bun CLIs and caches in the home directory.
        # Do not prepend ~/.cargo/bin: its rustup shims can shadow the
        # complete Nix toolchain installed above.
        sessionPath = [
          "${config.home.homeDirectory}/.bun/bin"
        ];
        sessionVariables = {
          BUN_INSTALL = "${config.home.homeDirectory}/.bun";
          # rust-src is provided separately by Nix and is not inside rustc's sysroot.
          RUST_SRC_PATH = "${pkgs.rustPlatform.rustcSrc}";
        };
      };

      home.file.".local/share/rust-toolchain".source = rustToolchain;
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
