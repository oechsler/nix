# Development Tools Configuration
#
# This module provides the development environment and optional GUI tooling:
#
# - Language toolchains and build tools (features.dev.enable = true)
# - Infrastructure tools (features.dev.enable = true)
# - JetBrains IDEs, DBeaver, and optional Android tooling
#
# Kubernetes tools (kubectl, helm, k9s) are configured in kubernetes.nix.

{
  config,
  pkgs,
  features,
  lib,
  ...
}:
let
  jetbrainsPackages = {
    inherit (pkgs) android-studio;
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
  androidComposition = pkgs.androidenv.composeAndroidPackages {
    platformVersions = [ "35" ];
    buildToolsVersions = [ "35.0.0" ];
    includeNDK = true;
    includeEmulator = true;
    includeSystemImages = true;
    systemImageTypes = [ "google_apis" ];
    abiVersions = [ "x86_64" ];
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
          # General development utilities
          cloc # Count lines of code

          # C/C++ toolchain
          clang # C compiler for native dependencies
          lld # LLVM linker for native dependencies

          # JVM toolchain
          gradle
          jdk
          kotlin

          # JavaScript/TypeScript toolchain
          bun # Runtime, package manager, and bunx (npx replacement)

          # Go toolchain
          go

          # Rust toolchain
          rustc
          cargo
          clippy
          rustfmt
          rustPlatform.rustcSrc # Rust standard library sources
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

    # Infrastructure tools
    (lib.mkIf features.dev.enable {
      home.packages = with pkgs; [
        ansible # Infrastructure automation
        opentofu # Terraform alternative (open-source)
      ];
    })

    # GUI development tools (only for desktop)
    (lib.mkIf (features.dev.enable && features.desktop.enable && features.dev.jetbrains.enable) {
      home.packages =
        with pkgs;
        (
          lib.optionals features.dev.dbeaver.enable [
            dbeaver-bin # Database GUI
          ]
          ++ map (name: lib.getAttr name jetbrainsPackages) (
            lib.filter (
              name: name != "android-studio" || features.dev.android.enable
            ) features.dev.jetbrains.entries
          )
        );
    })

    # Android Studio requires the Android flag, while the SDK can be enabled alone.
    (lib.mkIf
      (
        features.dev.enable
        && builtins.elem "android-studio" features.dev.jetbrains.entries
        && !features.dev.android.enable
      )
      {
        assertions = [
          {
            assertion = false;
            message = "features.dev.jetbrains.entries includes android-studio, but features.dev.android.enable is false.";
          }
        ];
      }
    )
    (lib.mkIf (features.dev.enable && features.dev.android.enable) {
      home = {
        packages = [ androidComposition.androidsdk ];
        sessionVariables = {
          ANDROID_HOME = "${androidComposition.androidsdk}/libexec/android-sdk";
          ANDROID_SDK_ROOT = "${androidComposition.androidsdk}/libexec/android-sdk";
        };
      };
    })
  ];
}
