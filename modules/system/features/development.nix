# Development tooling and editor feature options.

{ config, lib, ... }:

let
  development = import ../../lib/development.nix;
in
{
  options.features.dev = {
    enable = (lib.mkEnableOption "development tools") // {
      default = true;
    };
    languages = lib.mkOption {
      type = lib.types.listOf (lib.types.enum development.languageNames);
      default = [ ];
      description = "Development languages to enable; an empty list enables all languages.";
    };
    jetbrains = {
      enable = (lib.mkEnableOption "JetBrains IDEs") // {
        default = config.features.dev.enable;
      };
      entries = lib.mkOption {
        type = lib.types.listOf (
          lib.types.enum [
            "android-studio"
            "clion"
            "datagrip"
            "dataspell"
            "gateway"
            "goland"
            "idea-oss"
            "idea-ultimate"
            "mps"
            "phpstorm"
            "pycharm"
            "rider"
            "rubymine"
            "rustrover"
            "webstorm"
          ]
        );
        default = [
          "goland"
          "rustrover"
        ];
        description = "JetBrains IDEs to install.";
      };
    };
    android = {
      enable = (lib.mkEnableOption "Android development tooling") // {
        default = false;
      };
    };
    dbeaver = {
      enable = (lib.mkEnableOption "DBeaver database GUI") // {
        default = config.features.dev.enable;
      };
    };
  };

  config.nixpkgs.config = lib.mkIf config.features.dev.android.enable {
    android_sdk.accept_license = true;
  };
}
