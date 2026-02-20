# Package Management Configuration
#
# This module configures:
# 1. Flatpak - Universal package format with sandboxing
# 2. AppImage - Self-contained applications with auto-integration
#
# Configuration options:
#   features.flatpak.enable = true;    # Enable Flatpak (default: true)
#   features.appimage.enable = true;   # Enable AppImage (default: true)
#
# AppImage auto-integration:
#   - Drop .AppImage files into ~/Applications
#   - Desktop entries and icons are automatically created
#   - Shows up in application launchers (Rofi, KDE menu, etc.)
#   - Duplicate entries are automatically cleaned up

{ config, pkgs, lib, ... }:

{
  #===========================
  # Options
  #===========================

  options.features = {
    flatpak.enable = (lib.mkEnableOption "Flatpak support") // { default = true; };
    appimage.enable = (lib.mkEnableOption "AppImage support") // { default = true; };
  };

  #===========================
  # Configuration
  #===========================

  config = lib.mkMerge [

    #---------------------------
    # 1. Flatpak Support
    #---------------------------
    (lib.mkIf config.features.flatpak.enable {
      services.flatpak = {
        enable = true;
        remotes = [{
          name = "flathub";
          location = "https://flathub.org/repo/flathub.flatpakrepo";
        }];

        # Pre-installed Flatpaks
        packages = [
          "com.github.tchx84.Flatseal"        # Flatpak permission manager
          "io.github.giantpinkrobots.flatsweep"  # Flatpak cleanup tool
        ];
      };

      # Make Flatpak apps visible in application launchers
      environment.sessionVariables.XDG_DATA_DIRS = [ "/var/lib/flatpak/exports/share" ];

      # Flatpak GUI managers (KDE uses Discover, others use GNOME Software/Warehouse)
      environment.systemPackages = lib.mkIf (config.features.desktop.wm != "kde") (with pkgs; [
        gnome-software  # GTK Flatpak manager
        warehouse       # Modern GTK4 Flatpak manager
      ]);
    })

    #---------------------------
    # 2. AppImage Support
    #---------------------------
    (lib.mkIf config.features.appimage.enable {
      # Enable AppImage execution via binfmt
      programs.appimage = {
        enable = true;
        binfmt = true;  # Allows running AppImages without chmod +x
      };

      #---------------------------
      # AppImage Auto-Integration Service
      #---------------------------
      # Watches ~/Applications for .AppImage files and automatically:
      # 1. Creates .desktop entries in ~/.local/share/applications
      # 2. Extracts and installs icons
      # 3. Cleans up when AppImages are removed
      # 4. Removes duplicates when apps register their own entries
      #
      # How it works:
      # - Scans ~/Applications on startup for existing AppImages
      # - Uses inotifywait to watch for new/removed AppImages
      # - Extracts metadata using unsquashfs (no execution needed)
      # - Creates desktop entries with extracted name and icon
      # - Monitors ~/.local/share/applications for app-registered entries
      # - Removes our auto-generated entries when apps register their own

      systemd.user.services.appimage-watcher = {
        description = "Auto-integrate AppImages into desktop";
        wantedBy = [ "default.target" ];
        path = with pkgs; [ inotify-tools coreutils findutils gnused squashfsTools ];

        script = ''
          # Directories
          DIR="$HOME/Applications"                         # Where AppImages are stored
          DESKTOP_DIR="$HOME/.local/share/applications"    # Desktop entries
          ICON_DIR="$HOME/.local/share/icons/appimage"     # Extracted icons
          mkdir -p "$DIR" "$DESKTOP_DIR" "$ICON_DIR"

          # Function: Generate desktop entry for an AppImage
          #
          # Args:
          #   $1 = full path to .AppImage file
          #
          # Steps:
          #   1. Skip if app already registered its own .desktop entry
          #   2. Extract embedded .desktop file and icon using unsquashfs
          #   3. Parse Name from embedded .desktop or generate from filename
          #   4. Copy icon to ~/.local/share/icons/appimage/
          #   5. Create .desktop entry in ~/.local/share/applications/
          generate_entry() {
            local appimage="$1"
            local basename_file
            basename_file=$(basename "$appimage")
            local slug
            slug=$(echo "$basename_file" | sed 's/\.AppImage$//; s/\.appimage$//')

            chmod +x "$appimage"

            # Skip if the app already registered its own desktop entry
            # (We only create entries for apps that don't have one)
            local existing
            existing=$(grep -rl "$appimage" "$DESKTOP_DIR"/ 2>/dev/null | grep -v "^$DESKTOP_DIR/appimage-" | head -1)
            if [ -n "$existing" ]; then
              return
            fi

            # Extract metadata using unsquashfs (safe, doesn't execute the AppImage)
            # AppImages are SquashFS filesystems with metadata files inside
            local tmpdir
            tmpdir=$(mktemp -d)

            # Find the SquashFS offset in the AppImage
            local offset
            offset=$(grep -abo 'hsqs' "$appimage" 2>/dev/null | tail -1 | cut -d: -f1)

            if [ -n "$offset" ]; then
              # Extract only top-level .desktop files and icons (max-depth 1)
              unsquashfs -offset "$offset" -dest "$tmpdir/root" -max-depth 1 \
                "$appimage" '*.desktop' '*.png' '*.svg' '.DirIcon' &>/dev/null || true
            fi

            # Extract application name from embedded .desktop file
            local name=""
            local embedded_desktop
            embedded_desktop=$(find "$tmpdir/root" -maxdepth 1 -name '*.desktop' -type f 2>/dev/null | head -1)
            if [ -n "$embedded_desktop" ]; then
              name=$(sed -n 's/^Name=//p' "$embedded_desktop" | head -1)
            fi
            # Fallback: Generate name from filename (e.g., "my-app-1.2.3" → "my app 1.2.3")
            [ -z "$name" ] && name=$(echo "$slug" | sed 's/-/ /g; s/_/ /g')

            # Extract and install icon
            local icon="application-x-executable"  # Default icon if none found
            if [ -d "$tmpdir/root" ]; then
              local icon_file
              # Look for PNG or SVG icons
              icon_file=$(find "$tmpdir/root" -maxdepth 1 \( -name '*.png' -o -name '*.svg' \) -type f | head -1)
              # Fallback: .DirIcon (common in AppImages)
              [ -z "$icon_file" ] && icon_file=$(find "$tmpdir/root" -maxdepth 1 -name '.DirIcon' -type f | head -1)

              if [ -n "$icon_file" ]; then
                local ext
                ext=$(echo "$icon_file" | sed 's/.*\.//')
                [ "$ext" = "DirIcon" ] && ext="png"
                # Copy icon to our icon directory
                cp "$icon_file" "$ICON_DIR/$slug.$ext"
                icon="$ICON_DIR/$slug.$ext"
              fi
            fi

            rm -rf "$tmpdir"

            # Create desktop entry
            # Prefix with "appimage-" so we can identify our auto-generated entries
            local desktop_file="$DESKTOP_DIR/appimage-$basename_file.desktop"
            cat > "$desktop_file" <<EOF
[Desktop Entry]
Type=Application
Name=$name
Exec=$appimage
Terminal=false
Icon=$icon
Categories=Utility;
Comment=AppImage application
EOF
          }

          # Function: Remove desktop entry when AppImage is deleted
          #
          # Args:
          #   $1 = basename of .AppImage file (e.g., "app.AppImage")
          remove_entry() {
            local filename="$1"
            local icon_name
            icon_name=$(echo "$filename" | sed 's/\.AppImage$//; s/\.appimage$//')
            rm -f "$DESKTOP_DIR/appimage-$filename.desktop"
            rm -f "$ICON_DIR/$icon_name".*
          }

          # Function: Remove our auto-generated entries when app registers its own
          #
          # Some AppImages register their own desktop entries when first run.
          # We detect this and remove our auto-generated "appimage-*.desktop" entry
          # to avoid duplicates in the application launcher.
          cleanup_duplicates() {
            for desktop_file in "$DESKTOP_DIR"/appimage-*.desktop; do
              [ -f "$desktop_file" ] || continue

              # Get the AppImage path from our desktop entry
              local exec_path
              exec_path=$(sed -n 's/^Exec=//p' "$desktop_file" | head -1)
              [ -z "$exec_path" ] && continue

              # Check if there's another .desktop file (not ours) for the same AppImage
              local other
              other=$(grep -rl "$exec_path" "$DESKTOP_DIR"/ 2>/dev/null | grep -v "^$DESKTOP_DIR/appimage-" | head -1)

              if [ -n "$other" ]; then
                # App has its own entry now, remove ours
                local bname
                bname=$(basename "$desktop_file" .desktop | sed 's/^appimage-//')
                rm -f "$desktop_file"

                # Remove our extracted icon too
                local icon_name
                icon_name=$(echo "$bname" | sed 's/\.AppImage$//; s/\.appimage$//')
                rm -f "$ICON_DIR/$icon_name".*
              fi
            done
          }

          # Initial scan: Generate entries for existing AppImages
          find "$DIR" -maxdepth 1 -iname '*.appimage' -type f | while read -r f; do
            generate_entry "$f"
          done

          # Clean up stale entries (AppImage was deleted while service was not running)
          for desktop_file in "$DESKTOP_DIR"/appimage-*.desktop; do
            [ -f "$desktop_file" ] || continue
            appimage_name=$(basename "$desktop_file" .desktop | sed 's/^appimage-//')
            [ -f "$DIR/$appimage_name" ] || rm -f "$desktop_file"
          done
          cleanup_duplicates

          # Watch for changes using inotifywait
          # Monitors both ~/Applications (for .AppImage files) and ~/.local/share/applications (for app-registered entries)
          inotifywait -m -e create -e moved_to -e delete -e moved_from \
            "$DIR" "$DESKTOP_DIR" --format '%w|%e|%f' | while IFS='|' read -r watched_dir event filename; do

            if [ "$watched_dir" = "$DIR/" ]; then
              # Event in ~/Applications
              case "$filename" in
                *.AppImage|*.appimage)
                  case "$event" in
                    *DELETE*|*MOVED_FROM*)
                      # AppImage removed
                      remove_entry "$filename"
                      ;;
                    *)
                      # AppImage added/moved
                      generate_entry "$DIR/$filename"
                      ;;
                  esac
                  ;;
              esac

            elif [ "$watched_dir" = "$DESKTOP_DIR/" ]; then
              # Event in ~/.local/share/applications
              # Check if app registered its own desktop entry
              case "$filename" in
                appimage-*) ;;  # Ignore our own entries
                *.desktop) cleanup_duplicates ;;  # New .desktop file, check for duplicates
              esac
            fi
          done
        '';

        serviceConfig = {
          Restart = "on-failure";
          RestartSec = 5;
        };
      };
    })
  ];
}
