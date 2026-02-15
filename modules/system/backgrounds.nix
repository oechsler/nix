{ config, pkgs, lib, ... }:

let
  cfg = config.backgrounds;

  # The encrypted tar.gz file in the repo
  archiveFile = ../../backgrounds/blob.tar.gz.enc;

  # Script to extract and prepare wallpapers
  extractScript = pkgs.writeShellScript "extract-backgrounds" ''
    set -euo pipefail

    PASSWORD="$(cat ${config.sops.secrets."backgrounds/password".path})"
    OUTPUT_DIR="${cfg.outputDir}"
    WALLPAPER_NAME="${config.theme.wallpaper}"
    CURRENT="${cfg.outputDir}/${cfg.currentFile}"
    BLURRED="${cfg.outputDir}/${cfg.blurredFile}"

    mkdir -p "$OUTPUT_DIR"

    # Extract only the selected wallpaper from encrypted tar.gz
    ${pkgs.openssl}/bin/openssl enc -d -aes-256-cbc -pbkdf2 -pass pass:"$PASSWORD" < "${archiveFile}" | ${pkgs.gzip}/bin/gzip -d | ${pkgs.gnutar}/bin/tar xf - -C "$OUTPUT_DIR" "./$WALLPAPER_NAME"

    # Convert to jpg and create current.jpg
    ${pkgs.imagemagick}/bin/magick "$OUTPUT_DIR/$WALLPAPER_NAME" "$CURRENT"

    # Remove extracted original
    rm "$OUTPUT_DIR/$WALLPAPER_NAME"

    # Create blurred version for SDDM
    ${pkgs.imagemagick}/bin/magick "$CURRENT" -blur 0x30 "$BLURRED"

    # Set permissions
    chmod 644 "$CURRENT" "$BLURRED"
  '';
in
{
  options.backgrounds = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Extract wallpapers from encrypted archive at boot";
    };

    outputDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/backgrounds";
      description = "Directory where wallpapers are extracted to";
    };

    currentFile = lib.mkOption {
      type = lib.types.str;
      default = "current.jpg";
      description = "Filename for the processed current wallpaper";
    };

    blurredFile = lib.mkOption {
      type = lib.types.str;
      default = "current-blurred.jpg";
      description = "Filename for the blurred wallpaper";
    };
  };

  config = lib.mkMerge [
    # Always use consistent paths
    {
      theme.wallpaperPath = "${cfg.outputDir}/${cfg.currentFile}";
      theme.blurredWallpaperPath = "${cfg.outputDir}/${cfg.blurredFile}";
    }

    # Encrypted archive mode
    (lib.mkIf cfg.enable {
      sops.secrets."backgrounds/password" = {
        sopsFile = ../../sops/sops.encrypted.yaml;
      };

      systemd.services.extract-backgrounds = {
        description = "Extract encrypted wallpapers";
        wantedBy = [ "multi-user.target" ];
        before = [ "display-manager.service" ];
        after = [ "sops-nix.service" ];

        # Skip gracefully if SOPS key doesn't exist (fresh install)
        unitConfig.ConditionPathExists = config.sops.age.keyFile;

        serviceConfig = {
          Type = "oneshot";
          ExecStart = extractScript;
          RemainAfterExit = true;
        };
      };
    })

    # Fallback: link from store
    (lib.mkIf (!cfg.enable) {
      systemd.services.prepare-backgrounds = {
        description = "Prepare wallpapers from store";
        wantedBy = [ "multi-user.target" ];
        before = [ "display-manager.service" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = ''
          mkdir -p "${cfg.outputDir}"
          ${pkgs.imagemagick}/bin/magick "${config.theme.wallpaper}" "${cfg.outputDir}/${cfg.currentFile}"
          ${pkgs.imagemagick}/bin/magick "${cfg.outputDir}/${cfg.currentFile}" -blur 0x30 "${cfg.outputDir}/${cfg.blurredFile}"
          chmod 644 "${cfg.outputDir}/${cfg.currentFile}" "${cfg.outputDir}/${cfg.blurredFile}"
        '';
      };
    })
  ];
}
