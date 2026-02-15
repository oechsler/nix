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

    # Extract all wallpapers from encrypted tar.gz
    ${pkgs.openssl}/bin/openssl enc -d -aes-256-cbc -pbkdf2 -pass pass:"$PASSWORD" < "${archiveFile}" | ${pkgs.gzip}/bin/gzip -d | ${pkgs.gnutar}/bin/tar xf - -C "$OUTPUT_DIR"

    # Convert selected wallpaper to jpg and create current.jpg
    ${pkgs.imagemagick}/bin/magick "$OUTPUT_DIR/$WALLPAPER_NAME" "$CURRENT"

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

  config = lib.mkIf cfg.enable {
    # Secret for the ZIP password
    sops.secrets."backgrounds/password" = {
      sopsFile = ../../sops/sops.encrypted.yaml;
    };

    # Systemd service to extract wallpapers at boot
    systemd.services.extract-backgrounds = {
      description = "Extract encrypted wallpapers";
      wantedBy = [ "multi-user.target" ];
      before = [ "display-manager.service" ];
      after = [ "sops-nix.service" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = extractScript;
        RemainAfterExit = true;
      };
    };

    # Export paths for other modules
    theme.wallpaperPath = "${cfg.outputDir}/${cfg.currentFile}";
    theme.blurredWallpaperPath = "${cfg.outputDir}/${cfg.blurredFile}";
  };
}
