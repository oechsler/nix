# Wallpaper Management Configuration
#
# This module configures:
# 1. Encrypted wallpaper archive extraction (backgrounds.enable = true)
# 2. Direct wallpaper linking from Nix store (backgrounds.enable = false)
# 3. Catppuccin duotone color grading (backgrounds.catppuccinize.enable = true)
# 4. Blurred wallpaper generation for SDDM login screen
# 5. Fallback solid color when SOPS key is missing
#
# Configuration options:
#   backgrounds.enable = true;                        # Extract from encrypted archive (default: true)
#   backgrounds.catppuccinize.enable = true;          # Duotone color grading (default: true)
#   backgrounds.catppuccinize.flavor = "mocha";       # Shadow anchor (default: theme flavor)
#   backgrounds.catppuccinize.accent = "mauve";       # Highlight anchor (default: theme accent)
#   backgrounds.catppuccinize.baseTint = 22;          # Base-color overlay intensity 0–100 (default: 22)
#   backgrounds.outputDir = "/var/lib/backgrounds";   # Output directory
#   theme.wallpaper = "nix-black-4k.png";             # Wallpaper filename in archive or direct path
#
# Wallpaper archive:
#   Location: backgrounds/blob.tar.gz.enc (AES-256-CBC encrypted tar.gz)
#   Password: Stored in SOPS secret "backgrounds/password"
#
# Output files:
#   /var/lib/backgrounds/current.jpg         - Current wallpaper (Catppuccinized + JPG)
#   /var/lib/backgrounds/current-blurred.jpg - Catppuccinized + blurred for SDDM
#
# Catppuccin LUT (backgrounds.catppuccinize):
#   Grayscale duotone: black→flavor base, white→accent1.
#   A second accent (if set) is applied only to bright highlights
#   via a luma-threshold mask, keeping shadows pure duotone.
#   Then a base-color tint overlays the whole image.
#
# How it works (encrypted mode):
# - Decrypt backgrounds/blob.tar.gz.enc using OpenSSL
# - Extract selected wallpaper from tar.gz
# - Convert to JPG (if needed) and save as current.jpg
# - Apply Catppuccin duotone grade (if catppuccinize.enable = true)
# - Create blurred version for SDDM (blur radius 30)
# - Fallback to solid color (#181818) if SOPS key is missing
#
# How it works (direct mode):
# - Copy wallpaper from theme.wallpaper (path in Nix store)
# - Convert to JPG and apply Catppuccin LUT if enabled
# - Create blurred version
# - No encryption/decryption involved

{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.backgrounds;

  # ============================================================================
  # WALLPAPER ARCHIVE
  # ============================================================================
  # Encrypted tar.gz archive containing wallpapers
  # Encryption: AES-256-CBC with PBKDF2
  # Password: SOPS secret "backgrounds/password"
  archiveFile = ../../backgrounds/blob.tar.gz.enc;

  # ============================================================================
  # FALLBACK COLOR
  # ============================================================================
  # Neutral dark gray used when SOPS key is not available
  # Example: Fresh install before SOPS age key is set up
  fallbackColor = "#181818";

  # ============================================================================
  # CATPPUCCIN LUT COLORS
  # ============================================================================
  # Why: Catppuccinize wallpapers so every wallpaper matches the selected
  # flavor+accent automatically on nix rebuild.
  #
  # Approach: First convert to grayscale luminance, then apply a two-point
  # +level-colors with the flavor base and accent. This creates a cohesive
  # duotone effect: all original color information is stripped, and every
  # pixel is tinted on the base→accent spectrum.
  #
  # No saturation issues — there is no saturation after grayscale.
  # No separate -colorize — accent is already the white-point anchor.
  #
  #  black     → base    (flavor shadow, e.g. mocha #1e1e2e)
  #  white     → accent  (highlight tint, e.g. lavender #b4befe)
  #  midtones  → linear blend between base and accent
  catppuccinPalette = lib.importJSON "${config.catppuccin.sources.palette}/palette.json";
  catppuccinFlavorColors = catppuccinPalette.${cfg.catppuccinize.flavor}.colors;
  catppuccinBaseColor = catppuccinFlavorColors.base.hex;
  catppuccinAccentColor = catppuccinFlavorColors.${cfg.catppuccinize.accent}.hex;

  catppuccinizeStep = "${pkgs.imagemagick}/bin/magick \"$CURRENT\" -colorspace gray +level-colors \"${catppuccinBaseColor}\",\"${catppuccinAccentColor}\" -fill \"${catppuccinBaseColor}\" -colorize ${toString cfg.catppuccinize.baseTint}% \"$CURRENT\"";

  # ============================================================================
  # WALLPAPER EXTRACTION SCRIPT
  # ============================================================================
  # Why: Wallpapers are stored encrypted in the repository to keep them private.
  #
  # Problem: Encrypted wallpapers can't be used directly by desktop environments.
  #
  # Solution: Decrypt and extract wallpaper at boot before display manager starts.
  #
  # How it works:
  # 1. Check if SOPS secret is available
  #    - If not: Create solid color fallback (allows boot without secrets)
  #    - If yes: Proceed with decryption
  # 2. Decrypt archive using OpenSSL (AES-256-CBC)
  # 3. Extract selected wallpaper from tar.gz
  # 4. Convert to JPG (current.jpg)
  # 5. Create blurred version for SDDM (current-blurred.jpg)
  # 6. Clean up temporary files
  #
  # Result: Two wallpaper files ready for use:
  # - /var/lib/backgrounds/current.jpg (desktop wallpaper)
  # - /var/lib/backgrounds/current-blurred.jpg (SDDM login screen)
  extractScript = pkgs.writeShellScript "extract-backgrounds" ''
    set -euo pipefail

    SECRET_FILE="${config.sops.secrets."backgrounds/password".path}"
    OUTPUT_DIR="${cfg.outputDir}"
    WALLPAPER_NAME="${config.theme.wallpaper}"
    CURRENT="${cfg.outputDir}/${cfg.currentFile}"
    BLURRED="${cfg.outputDir}/${cfg.blurredFile}"

    mkdir -p "$OUTPUT_DIR"

    # Check if SOPS secret is available (age key set up)
    if [[ ! -f "$SECRET_FILE" ]]; then
      echo "SOPS secret not available, creating fallback wallpaper"
      # Create solid color wallpaper (4K resolution)
      ${pkgs.imagemagick}/bin/magick -size 3840x2160 xc:"${fallbackColor}" "$CURRENT"
      cp "$CURRENT" "$BLURRED"
      chmod 644 "$CURRENT" "$BLURRED"
      exit 0
    fi

    # Read decryption password from SOPS secret
    PASSWORD="$(cat "$SECRET_FILE")"

    # Decrypt and extract wallpaper
    # Pipeline: decrypt (openssl) → decompress (gzip) → extract (tar)
    ${pkgs.openssl}/bin/openssl enc -d -aes-256-cbc -pbkdf2 -pass pass:"$PASSWORD" < "${archiveFile}" | \
      ${pkgs.gzip}/bin/gzip -d | \
      ${pkgs.gnutar}/bin/tar xf - -C "$OUTPUT_DIR" "./$WALLPAPER_NAME"

    # Convert to JPG and save as current.jpg
    # ImageMagick handles any format (PNG, JPG, etc.)
    ${pkgs.imagemagick}/bin/magick "$OUTPUT_DIR/$WALLPAPER_NAME" "$CURRENT"

    # Remove extracted original (keep only current.jpg)
    rm "$OUTPUT_DIR/$WALLPAPER_NAME"

    # Apply Catppuccin duotone: grayscale → level-colors(base,accent) → base tint
    if ${if cfg.catppuccinize.enable then "true" else "false"}; then
      ${catppuccinizeStep}
    fi

    # Create blurred version for SDDM login screen
    # Blur radius: 30 pixels (strong blur for background aesthetics)
    ${pkgs.imagemagick}/bin/magick "$CURRENT" -blur 0x30 "$BLURRED"

    # Set world-readable permissions (needed for display manager)
    chmod 644 "$CURRENT" "$BLURRED"

    # Signal user-level awww to reload (see awww.nix path unit)
    touch "/var/lib/backgrounds/.reload"
    chmod 666 "/var/lib/backgrounds/.reload"
  '';
in
{
  #===========================
  # Options
  #===========================

  options.backgrounds = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Extract wallpapers from encrypted archive at boot (false = use direct path from theme.wallpaper)";
    };

    outputDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/backgrounds";
      description = "Directory where wallpapers are extracted to";
    };

    currentFile = lib.mkOption {
      type = lib.types.str;
      default = "current.jpg";
      description = "Filename for the processed current wallpaper (converted to JPG)";
    };

    blurredFile = lib.mkOption {
      type = lib.types.str;
      default = "current-blurred.jpg";
      description = "Filename for the blurred wallpaper (used by SDDM login screen)";
    };

    catppuccinize = lib.mkOption {
      type = lib.types.submodule {
        options = {
          enable = lib.mkEnableOption "apply a Catppuccin duotone grade to wallpapers" // {
            default = true;
          };

          flavor = lib.mkOption {
            type = lib.types.str;
            default = config.theme.catppuccin.flavor;
            description = "Catppuccin flavor used as the shadow anchor.";
          };

          accent = lib.mkOption {
            type = lib.types.str;
            default = config.theme.catppuccin.accent;
            description = "Catppuccin accent used as the duotone highlight anchor.";
          };

          baseTint = lib.mkOption {
            type = lib.types.ints.between 0 100;
            default = 22;
            description = "Percentage of base color applied over the duotone result.";
          };
        };
      };
      default = { };
      description = "Catppuccin wallpaper color-grade settings.";
    };
  };

  #===========================
  # Configuration
  #===========================

  config = lib.mkMerge [

    #---------------------------
    # 1. Wallpaper Paths (Always Set)
    #---------------------------
    # These paths are used by desktop environments, SDDM, and other modules
    # They point to the processed wallpapers, regardless of source (encrypted or direct)
    {
      theme.wallpaperPath = "${cfg.outputDir}/${cfg.currentFile}";
      theme.blurredWallpaperPath = "${cfg.outputDir}/${cfg.blurredFile}";
    }

    #---------------------------
    # 2. Encrypted Archive Mode
    #---------------------------
    (lib.mkIf cfg.enable {
      sops.secrets."backgrounds/password" = { };

      systemd.services.extract-backgrounds = {
        description = "Extract encrypted wallpapers";
        wantedBy = [ "multi-user.target" ];
        before = [ "display-manager.service" ];
        after = [
          "local-fs.target" # /persist must be mounted before writing wallpapers
          "sops-install-secrets.service"
        ];
        unitConfig.ConditionPathExists = config.sops.age.keyFile;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = extractScript;
          RemainAfterExit = true;
        };
      };
    })

    #---------------------------
    # 3. Direct Mode (No Encryption)
    #---------------------------
    # Copy wallpaper directly from Nix store (theme.wallpaper path)
    # Useful for testing or when encryption is not desired
    (lib.mkIf (!cfg.enable) {
      systemd.services.prepare-backgrounds = {
        description = "Prepare wallpapers from store";
        wantedBy = [ "multi-user.target" ];
        before = [ "display-manager.service" ];
        after = [ "local-fs.target" ]; # /persist must be mounted before writing wallpapers

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = ''
          set -euo pipefail

          mkdir -p "${cfg.outputDir}"
          CURRENT="${cfg.outputDir}/${cfg.currentFile}"
          BLURRED="${cfg.outputDir}/${cfg.blurredFile}"

          # Convert wallpaper to JPG and save as current.jpg
          ${pkgs.imagemagick}/bin/magick "${config.theme.wallpaper}" "$CURRENT"

          # Apply Catppuccin duotone: grayscale → level-colors(base,accent) → base tint
          if ${if cfg.catppuccinize.enable then "true" else "false"}; then
            ${catppuccinizeStep}
          fi

          # Create blurred version for SDDM (blur radius 30)
          ${pkgs.imagemagick}/bin/magick "$CURRENT" -blur 0x30 "$BLURRED"

          # Set world-readable permissions
          chmod 644 "$CURRENT" "$BLURRED"
        '';
      };
    })
  ];
}
