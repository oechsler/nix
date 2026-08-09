# Wallpaper Management Configuration
#
# This module configures:
# 1. Encrypted wallpaper archive extraction (theme.backgrounds.enable = true)
# 2. Direct wallpaper linking from Nix store (theme.backgrounds.enable = false)
# 3. Catppuccin color grading via gowall (theme.backgrounds.catppuccinize.enable = true)
# 4. Blurred wallpaper generation for SDDM login screen
# 5. Fallback solid color when SOPS key is missing
#
# Configuration options:
#   theme.backgrounds.enable = true;                        # Extract from encrypted archive (default: true)
#   theme.backgrounds.catppuccinize.enable = true;          # Catppuccin color grade via gowall (default: true)
#   theme.backgrounds.outputDir = "/var/lib/backgrounds";   # Output directory
#   theme.backgrounds.path = "nix-black-4k.png";           # Wallpaper filename in archive or direct path
#
# Catppuccin color grading (theme.backgrounds.catppuccinize):
#   Uses gowall with a custom wallpaper theme driven by theme.backgrounds.catppuccinize.accent:
#   - null               → all 14 real accent colours of the flavour (unshaded).
#   - ["lavender"]        → 14 brightness-shaded variants of lavender (single-accent).
#   - ["blue" "lavender"] → 14 slots cycled from the given accents, each shaded.
#   Defaults to [<system accent>], so the old single-accent behaviour is preserved.
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
# - Apply gowall Catppuccin grade (if theme.backgrounds.catppuccinize.enable is true)
# - Create blurred version for SDDM (blur radius 30)
# - Fallback to solid color (#181818) if SOPS key is missing
#
# How it works (direct mode):
# - Copy wallpaper from theme.backgrounds.path (path in Nix store)
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
  outputDir = "/var/lib/backgrounds";
  currentFile = "current.jpg";
  blurredFile = "current-blurred.jpg";

  wallpaperPath = config.theme.backgrounds.path;
  isUrl = lib.hasPrefix "http://" wallpaperPath || lib.hasPrefix "https://" wallpaperPath;

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
  # Generate a wallpaper gowall theme driven by theme.backgrounds.catppuccinize.accent:
  # - null               → all 14 real accent colours of the flavour (unshaded).
  # - ["lavender"]        → 14 brightness-shaded variants of lavender (single-accent).
  # - ["blue" "lavender"] → 14 slots cycled from the given accents, each shaded.
  # Defaults to [<system accent>], so the old single-accent behaviour is preserved.

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

  wallpaperAccents = config.theme.backgrounds.catppuccinize.accent;
  wallpaperThemeJSON =
    let
      palette = lib.importJSON "${config.catppuccin.sources.palette}/palette.json";
      flavorC = palette.${config.catppuccin.flavor}.colors;

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

      accentColors =
        if wallpaperAccents == null then
          map (name: flavorC.${name}.hex) [
            "rosewater"
            "flamingo"
            "pink"
            "mauve"
            "red"
            "maroon"
            "peach"
            "yellow"
            "green"
            "teal"
            "sky"
            "sapphire"
            "blue"
            "lavender"
          ]
        else
          let
            numAccents = builtins.length wallpaperAccents;
          in
          lib.imap0 (
            idx: _:
            let
              acc = builtins.elemAt wallpaperAccents (lib.mod idx numAccents);
              accRgb = hexToRgb flavorC.${acc}.hex;
              factor = builtins.elemAt accentFactors idx;
            in
            rgbToHex (shadeRgb accRgb factor)
          ) accentFactors;

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
      themeName =
        if wallpaperAccents == null then
          "catppuccin-wallpaper-${config.catppuccin.flavor}-all"
        else
          "catppuccin-wallpaper-${config.catppuccin.flavor}-${lib.concatStringsSep "-" wallpaperAccents}";
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
        if config.theme.backgrounds.catppuccinize.invert then
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
    OUTPUT_DIR="${outputDir}"
    WALLPAPER_NAME="${config.theme.backgrounds.path}"
    CURRENT="${outputDir}/${currentFile}"
    BLURRED="${outputDir}/${blurredFile}"

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
    if ${if config.theme.backgrounds.catppuccinize.enable then "true" else "false"}; then
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

  options.theme.backgrounds = {
    path = lib.mkOption {
      type = lib.types.either lib.types.path lib.types.str;
      default = "nix-black-4k.png";
      description = "Wallpaper: filename in encrypted archive, direct path to a file, or URL to download";
    };

    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Extract wallpapers from encrypted archive at boot (false = use direct path from theme.backgrounds.path)";
    };

    catppuccinize = {
      enable = lib.mkEnableOption "apply Catppuccin color grading to wallpapers via gowall" // {
        default = true;
      };

      invert = lib.mkEnableOption "invert wallpaper colors before gowall LUT mapping" // {
        default = false;
      };

      accent = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.listOf (
            lib.types.enum [
              "rosewater"
              "flamingo"
              "pink"
              "mauve"
              "red"
              "maroon"
              "peach"
              "yellow"
              "green"
              "teal"
              "sky"
              "sapphire"
              "blue"
              "lavender"
            ]
          )
        );
        default = [ config.catppuccin.accent ];
        description = ''
          Wallpaper accent colors for gowall LUT mapping.
          - null: use the actual palette accent colors of the flavour (all 14).
          - ["lavender"]: shade the system accent across all 14 slots (default behaviour).
          - ["blue" "lavender"]: use only those accents, cycled across the 14 slots.
        '';
      };
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
      theme.wallpaperPath = "${outputDir}/${currentFile}";
      theme.blurredWallpaperPath = "${outputDir}/${blurredFile}";
    }

    #---------------------------
    # 2. URL Download Mode
    #---------------------------
    # Download wallpaper from a URL, regardless of archive setting.
    (lib.mkIf isUrl {
      systemd.services.download-wallpaper = {
        description = "Download wallpaper from URL";
        wantedBy = [ "multi-user.target" ];
        before = [ "display-manager.service" ];
        after = [ "local-fs.target" ];

        environment = {
          HOME = outputDir;
          XDG_CONFIG_HOME = "${outputDir}/.config";
        };
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = ''
          set -euo pipefail

          mkdir -p "${outputDir}"
          CURRENT="${outputDir}/${currentFile}"
          BLURRED="${outputDir}/${blurredFile}"

          ${pkgs.curl}/bin/curl -fsSL -o "$CURRENT" "${wallpaperPath}"

          # Apply Catppuccin color grade via gowall
          if ${if config.theme.backgrounds.catppuccinize.enable then "true" else "false"}; then
            ${catppuccinizeStep}
          fi

          # Create blurred version for SDDM (blur radius 30)
          ${pkgs.imagemagick}/bin/magick "$CURRENT" -blur 0x30 "$BLURRED"

          # Set world-readable permissions
          chmod 644 "$CURRENT" "$BLURRED"

          # Signal user-level awww to reload (see awww.nix path unit)
          touch "/var/lib/backgrounds/.reload"
          chmod 666 "/var/lib/backgrounds/.reload"
        '';
      };
    })

    #---------------------------
    # 3. Encrypted Archive Mode
    #---------------------------
    (lib.mkIf (config.theme.backgrounds.enable && !isUrl) {
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
          HOME = outputDir;
          XDG_CONFIG_HOME = "${outputDir}/.config";
        };
        serviceConfig = {
          Type = "oneshot";
          ExecStart = extractScript;
          RemainAfterExit = true;
        };
      };
    })

    #---------------------------
    # 4. Direct Mode (No Encryption)
    #---------------------------
    # Copy wallpaper directly from Nix store (theme.backgrounds.path)
    # Useful for testing or when encryption is not desired
    (lib.mkIf (!config.theme.backgrounds.enable && !isUrl) {
      systemd.services.prepare-backgrounds = {
        description = "Prepare wallpapers from store";
        wantedBy = [ "multi-user.target" ];
        before = [ "display-manager.service" ];
        after = [ "local-fs.target" ]; # /persist must be mounted before writing wallpapers

        environment = {
          HOME = outputDir;
          XDG_CONFIG_HOME = "${outputDir}/.config";
        };
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = ''
          set -euo pipefail

          mkdir -p "${outputDir}"
          CURRENT="${outputDir}/${currentFile}"
          BLURRED="${outputDir}/${blurredFile}"

          # Convert wallpaper to JPG and save as current.jpg
          ${pkgs.imagemagick}/bin/magick "${wallpaperPath}" "$CURRENT"

          # Apply Catppuccin color grade via gowall
          if ${if config.theme.backgrounds.catppuccinize.enable then "true" else "false"}; then
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
