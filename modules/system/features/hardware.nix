# Hardware and boot feature options.

{ config, lib, ... }:

{
  options.features = {
    hardware = {
      formFactor = lib.mkOption {
        type = lib.types.enum [
          "desktop"
          "laptop"
        ];
        default = "desktop";
        description = ''
          Machine form factor — selects machine-type-specific behavior:

          "desktop"
            - Lid switch → ignore (no lid on a desktop)
            - AMD GPU → runpm=0 (disable GPU runtime PM, prevents resume hangs)
            - Power key → suspend

          "laptop"
            - Lid switch → suspend on battery, ignore on external power
            - AMD GPU → runtime PM enabled (keeps battery alive)
            - Power key → suspend

        '';
      };

      cpu = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.enum [
            "amd"
            "intel"
          ]
        );
        default = null;
        description = "CPU vendor — enables the correct microcode update package (security patches from AMD/Intel loaded at early boot).";
      };
      gpu = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.enum [
            "amd"
            "intel"
          ]
        );
        default = null;
        description = "GPU vendor — enables graphics support and the correct VA-API driver for hardware video decoding. AMD also gets 32-bit libs when gaming is enabled. NVIDIA is not supported.";
      };
    };

    impermanence = {
      enable = (lib.mkEnableOption "impermanent root with rollback on boot") // {
        default = true;
      };
      persistPrefix = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        default = if config.features.impermanence.enable then "/persist" else "";
        description = "Path prefix for persistent files. '/persist' when impermanence is active, '' otherwise. Use this for files that must bypass bind-mounts (e.g., pam_oath usersfile).";
      };
      extraPaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Additional paths to persist (beyond feature-based defaults)";
        example = [
          "/var/lib/custom-app"
          "/etc/custom-config"
        ];
      };
    };
  };
}
