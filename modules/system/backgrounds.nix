# Wallpaper Management Configuration
#
# This module configures:
# 1. Encrypted wallpaper archive extraction (backgrounds.enable = true)
# 2. Direct wallpaper linking from Nix store (backgrounds.enable = false)
# 3. Catppuccin color grading via gowall (catppuccinize.background.enable = true)
# 4. Blurred wallpaper generation for SDDM login screen
# 5. Fallback solid color when SOPS key is missing
#
# Configuration options:
#   backgrounds.enable = true;                        # Extract from encrypted archive (default: true)
#   catppuccinize.background.enable = true;          # Catppuccin color grade via gowall (default: true)
#   backgrounds.outputDir = "/var/lib/backgrounds";   # Output directory
#   theme.wallpaper = "nix-black-4k.png";             # Wallpaper filename in archive or direct path
#
# Catppuccin color grading (catppuccinize.background):
#   Uses gowall with a custom wallpaper theme where all 14 accent slots
#   are shades of the system accent color. Surface/base colors stay from the flavor palette.
#   This emphasizes a single accent color while keeping the catppuccin gray tones.
#
# Wallpaper archive:
#   Location: backgrounds/blob.tar.gz.enc (AES-256-CBC encrypted tar.gz)
#   Password: Stored in SOPS secret "backgrounds/password"
#
# Output files:
#   /var/lib/backgrounds/current.jpg         - Current wallpaper (Catppuccinized + JPG)
#   /var/lib/backgrounds/current-blurred.jpg - Catppuccinized + blurred for SDDM
#
# How it works (encrypted mode):
# - Decrypt backgrounds/blob.tar.gz.enc using OpenSSL
# - Extract selected wallpaper from tar.gz
# - Convert to JPG (if needed) and save as current.jpg
# - Apply gowall Catppuccin grade (if catppuccinize.enable && catppuccinize.background.enable are true)
# - Create blurred version for SDDM (blur radius 30)
# - Fallback to solid color (#181818) if SOPS key is missing
#
# How it works (direct mode):
# - Copy wallpaper from theme.wallpaper (path in Nix store)
# - Convert to JPG and apply gowall Catppuccin grade if enabled
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
  # WALLPAPER GOWALL THEME
  # ============================================================================
  # Generate a wallpaper gowall theme where all 14 accent-color slots are shades
  # of the system accent color. Surface/base colors stay the same as the global theme.
  # This emphasizes a single accent color while keeping the catppuccin gray tones.

  hexMap = {
    "0" = 0;
    "1" = 1;
    "2" = 2;
    "3" = 3;
    "4" = 4;
    "5" = 5;
    "6" = 6;
    "7" = 7;
    "8" = 8;
    "9" = 9;
    "a" = 10;
    "b" = 11;
    "c" = 12;
    "d" = 13;
    "e" = 14;
    "f" = 15;
  };
  hexByte = s: hexMap.${builtins.substring 0 1 s} * 16 + hexMap.${builtins.substring 1 1 s};
  hexToRgb =
    hex:
    let
      h = lib.removePrefix "#" hex;
    in
    {
      r = hexByte (builtins.substring 0 2 h);
      g = hexByte (builtins.substring 2 2 h);
      b = hexByte (builtins.substring 4 2 h);
    };
  hexDigits = [
    "0"
    "1"
    "2"
    "3"
    "4"
    "5"
    "6"
    "7"
    "8"
    "9"
    "a"
    "b"
    "c"
    "d"
    "e"
    "f"
  ];
  toHexByte =
    n: "${builtins.elemAt hexDigits (n / 16)}${builtins.elemAt hexDigits (n - (n / 16) * 16)}";
  rgbToHex = c: "#${toHexByte c.r}${toHexByte c.g}${toHexByte c.b}";
  shadeRgb = c: f: {
    r = builtins.floor (c.r * f);
    g = builtins.floor (c.g * f);
    b = builtins.floor (c.b * f);
  };

  wallpaperAccent = config.catppuccin.accent;
  wallpaperThemeJSON =
    let
      palette = lib.importJSON "${config.catppuccin.sources.palette}/palette.json";
      flavorC = palette.${config.catppuccin.flavor}.colors;
      accentRgb = hexToRgb flavorC.${wallpaperAccent}.hex;

      accentFactors = [
        0.08
        0.12
        0.16
        0.22
        0.30
        0.40
        0.50
        0.60
        0.70
        0.80
        0.90
        0.95
        1.0
        1.0
      ];
      accentColors = map (f: rgbToHex (shadeRgb accentRgb f)) accentFactors;

      surfaceOrder = [
        "text"
        "subtext1"
        "subtext0"
        "overlay2"
        "overlay1"
        "overlay0"
        "surface2"
        "surface1"
        "surface0"
        "base"
        "mantle"
        "crust"
      ];
      surfaceColors = map (name: flavorC.${name}.hex) surfaceOrder;

      colors = accentColors ++ surfaceColors;
      themeName = "catppuccin-wallpaper-${config.catppuccin.flavor}-${wallpaperAccent}";
    in
    pkgs.writeText "gowall-${themeName}.json" (
      builtins.toJSON {
        name = themeName;
        inherit colors;
      }
    );

  catppuccinizeStep =
    let
      invertStep =
        if config.catppuccinize.background.invert then
          "${pkgs.gowall}/bin/gowall invert \"$CURRENT\" --yes && "
        else
          "";
    in
    "${invertStep}${pkgs.gowall}/bin/gowall convert \"$CURRENT\" --theme ${wallpaperThemeJSON} --output \"$CURRENT\" --yes";

  # ============================================================================
  # WALLPAPER EXTRACTION SCRIPT
  # ============================================================================
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

    # Apply Catppuccin color grade via gowall
    if ${
      if config.catppuccinize.enable && config.catppuccinize.background.enable then "true" else "false"
    }; then
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
        environment = {
          HOME = cfg.outputDir;
          XDG_CONFIG_HOME = "${cfg.outputDir}/.config";
        };
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

        environment = {
          HOME = cfg.outputDir;
          XDG_CONFIG_HOME = "${cfg.outputDir}/.config";
        };
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

          # Apply Catppuccin color grade via gowall
          if ${
            if config.catppuccinize.enable && config.catppuccinize.background.enable then "true" else "false"
          }; then
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
