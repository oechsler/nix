# Wallpaper Management Configuration
#
# This module configures:
# 1. Auto-detection: encrypted archive → fallback to Nix store path
# 2. URL download (theme.backgrounds.path = "https://...")
# 3. Catppuccin color grading via gowall (theme.backgrounds.catppuccinize.enable = true)
# 4. Blurred wallpaper generation for SDDM login screen
# 5. Fallback solid color when SOPS key is missing
#
# Modes (auto-detected from theme.backgrounds.path):
#   URL (http:// or https://) → download via curl
#   Otherwise                 → try archive extraction first,
#                                fall back to direct Nix store path
#
# Configuration options:
#   theme.backgrounds.path = "nix-black-4k.png";           # Filename in archive, path, or URL
#   theme.backgrounds.catppuccinize.enable = true;          # Catppuccin color grade via gowall (default: true)
#   theme.backgrounds.outputDir = "/var/lib/backgrounds";   # Output directory (derived)
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
# How it works:
# - If path is a URL → download via curl
# - If SOPS key is available → try to decrypt archive and extract the file
# - If archive extraction fails (wrong password, file not found) → fall back to direct path
# - If no SOPS key → fall back to direct path;
#   if that also fails → solid color fallback
# - Convert to JPG (if needed) and save as current.jpg
# - Apply gowall Catppuccin grade (if theme.backgrounds.catppuccinize.enable is true)
# - Create blurred version for SDDM (blur radius 30)

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
  # WALLPAPER PREPARATION SCRIPT
  # ============================================================================
  # Tries archive extraction first, falls back to direct Nix store path if:
  # - SOPS key is unavailable
  # - Password is wrong
  # - File is not in the archive
  prepareScript = pkgs.writeShellScript "prepare-wallpaper" ''
    set -euo pipefail

    SECRET_FILE="${config.sops.secrets."backgrounds/password".path}"
    OUTPUT_DIR="${outputDir}"
    CURRENT="${outputDir}/${currentFile}"
    BLURRED="${outputDir}/${blurredFile}"

    mkdir -p "$OUTPUT_DIR"

    archive_ok=0

    if [[ -f "$SECRET_FILE" ]]; then
      if ${pkgs.openssl}/bin/openssl enc -d -aes-256-cbc -pbkdf2 -pass file:"$SECRET_FILE" \
           < "${archiveFile}" 2>/dev/null \
        | ${pkgs.gzip}/bin/gzip -d 2>/dev/null \
        | ${pkgs.gnutar}/bin/tar tf - 2>/dev/null \
        | ${pkgs.gnugrep}/bin/grep -qxF "./${wallpaperPath}"; then
        echo "Extracting ${wallpaperPath} from archive"
        ${pkgs.openssl}/bin/openssl enc -d -aes-256-cbc -pbkdf2 -pass file:"$SECRET_FILE" \
          < "${archiveFile}" \
        | ${pkgs.gzip}/bin/gzip -d \
        | ${pkgs.gnutar}/bin/tar xf - -C "$OUTPUT_DIR" "./${wallpaperPath}"
        ${pkgs.imagemagick}/bin/magick "$OUTPUT_DIR/${wallpaperPath}" "$CURRENT"
        rm "$OUTPUT_DIR/${wallpaperPath}"
        archive_ok=1
      fi
    else
      echo "No SOPS key, skipping archive extraction"
    fi

    if [[ $archive_ok -eq 0 ]]; then
      if [[ -f "${wallpaperPath}" ]]; then
        echo "Using direct path: ${wallpaperPath}"
        ${pkgs.imagemagick}/bin/magick "${wallpaperPath}" "$CURRENT" 2>/dev/null || {
          echo "Direct path failed, using solid color fallback"
          ${pkgs.imagemagick}/bin/magick -size 3840x2160 xc:"${fallbackColor}" "$CURRENT"
        }
      else
        echo "No wallpaper source available, using solid color fallback"
        ${pkgs.imagemagick}/bin/magick -size 3840x2160 xc:"${fallbackColor}" "$CURRENT"
      fi
    fi

    # Apply Catppuccin color grade via gowall
    if ${if config.theme.backgrounds.catppuccinize.enable then "true" else "false"}; then
      ${catppuccinizeStep}
    fi

    # Create blurred version for SDDM login screen
    ${pkgs.imagemagick}/bin/magick "$CURRENT" -blur 0x30 "$BLURRED"

    # Set world-readable permissions
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
      description = "Wallpaper: filename in encrypted archive, direct path, or URL to download";
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
    {
      theme.wallpaperPath = "${outputDir}/${currentFile}";
      theme.blurredWallpaperPath = "${outputDir}/${blurredFile}";
    }

    #---------------------------
    # 2. URL Download Mode
    #---------------------------
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
    # 3. Archive + Direct Mode (Non-URL)
    #---------------------------
    # Tries archive extraction first; falls back to direct Nix store path
    (lib.mkIf (!isUrl) {
      sops.secrets."backgrounds/password" = { };

      systemd.services.prepare-wallpaper = {
        description = "Prepare wallpaper (archive or direct)";
        wantedBy = [ "multi-user.target" ];
        before = [ "display-manager.service" ];
        after = [
          "local-fs.target"
          "sops-install-secrets.service"
        ];

        environment = {
          HOME = outputDir;
          XDG_CONFIG_HOME = "${outputDir}/.config";
        };
        serviceConfig = {
          Type = "oneshot";
          ExecStart = prepareScript;
          RemainAfterExit = true;
        };
      };
    })
  ];
}
