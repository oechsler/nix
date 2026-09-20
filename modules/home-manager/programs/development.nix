# Development Tools Configuration
#
# This module provides the development environment and optional GUI tooling:
#
# - Language toolchains and build tools (features.dev.enable = true)
# - GitHub CLI and GitUI (features.dev.enable = true)
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
in
{
  #===========================
  # Configuration
  #===========================

  config = lib.mkMerge [
    # CLI Development Tools (always useful, even on servers)
    (lib.mkIf features.dev.enable {
      programs = {
        gh = {
          enable = true;
          gitCredentialHelper.enable = false;
          settings.git_protocol = "https";
        };
        gitui.enable = true;
      };

      home = {
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
      home.activation.androidSdkDirectory = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        mkdir -p "$HOME/Android/Sdk"
      '';
      home.sessionVariables = {
        ANDROID_HOME = "${config.home.homeDirectory}/Android/Sdk";
        ANDROID_SDK_ROOT = "${config.home.homeDirectory}/Android/Sdk";
      };

      # The SDK emulator ships an XCB Qt plugin but no Wayland plugin. Keep
      # the workaround scoped to Android Studio and its child processes.
      xdg.desktopEntries.android-studio = {
        name = "Android Studio";
        exec = "env QT_QPA_PLATFORM=xcb android-studio %U";
        icon = "android-studio";
        terminal = false;
        categories = [
          "Development"
          "IDE"
        ];
      };
    })
  ];
}
