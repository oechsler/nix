{ config, pkgs, lib, ... }:

{
  options.features = {
    flatpak.enable = (lib.mkEnableOption "Flatpak support") // { default = true; };
    appimage.enable = (lib.mkEnableOption "AppImage support") // { default = true; };
  };

  config = lib.mkMerge [
    (lib.mkIf config.features.flatpak.enable {
      services.flatpak = {
        enable = true;
        remotes = [{
          name = "flathub";
          location = "https://flathub.org/repo/flathub.flatpakrepo";
        }];
        packages = [
          "com.github.tchx84.Flatseal"
          "io.github.giantpinkrobots.flatsweep"
        ];
      };

      environment.sessionVariables.XDG_DATA_DIRS = [ "/var/lib/flatpak/exports/share" ];

      # KDE uses Discover for Flatpak management
      environment.systemPackages = lib.mkIf (config.features.desktop.wm != "kde") (with pkgs; [
        gnome-software
        warehouse
      ]);
    })

    (lib.mkIf config.features.appimage.enable {
      programs.appimage = {
        enable = true;
        binfmt = true;
      };

      # Watch ~/Applications for AppImages and auto-create .desktop entries
      systemd.user.services.appimage-watcher = {
        description = "Auto-integrate AppImages into desktop";
        wantedBy = [ "default.target" ];
        path = with pkgs; [ inotify-tools coreutils findutils gnused squashfsTools ];
        script = ''
          DIR="$HOME/Applications"
          DESKTOP_DIR="$HOME/.local/share/applications"
          ICON_DIR="$HOME/.local/share/icons/appimage"
          mkdir -p "$DIR" "$DESKTOP_DIR" "$ICON_DIR"

          generate_entry() {
            local appimage="$1"
            local basename_file
            basename_file=$(basename "$appimage")
            local slug
            slug=$(echo "$basename_file" | sed 's/\.AppImage$//; s/\.appimage$//')

            chmod +x "$appimage"

            # Skip if the app already registered its own desktop entry
            local existing
            existing=$(grep -rl "$appimage" "$DESKTOP_DIR"/ 2>/dev/null | grep -v "^$DESKTOP_DIR/appimage-" | head -1)
            if [ -n "$existing" ]; then
              return
            fi

            # Extract metadata using unsquashfs (doesn't execute the AppImage)
            local tmpdir
            tmpdir=$(mktemp -d)
            local offset
            offset=$(grep -abo 'hsqs' "$appimage" 2>/dev/null | tail -1 | cut -d: -f1)
            if [ -n "$offset" ]; then
              unsquashfs -offset "$offset" -dest "$tmpdir/root" -max-depth 1 \
                "$appimage" '*.desktop' '*.png' '*.svg' '.DirIcon' &>/dev/null || true
            fi

            # Extract name from embedded .desktop file
            local name=""
            local embedded_desktop
            embedded_desktop=$(find "$tmpdir/root" -maxdepth 1 -name '*.desktop' -type f 2>/dev/null | head -1)
            if [ -n "$embedded_desktop" ]; then
              name=$(sed -n 's/^Name=//p' "$embedded_desktop" | head -1)
            fi
            [ -z "$name" ] && name=$(echo "$slug" | sed 's/-/ /g; s/_/ /g')

            # Extract icon
            local icon="application-x-executable"
            if [ -d "$tmpdir/root" ]; then
              local icon_file
              icon_file=$(find "$tmpdir/root" -maxdepth 1 \( -name '*.png' -o -name '*.svg' \) -type f | head -1)
              [ -z "$icon_file" ] && icon_file=$(find "$tmpdir/root" -maxdepth 1 -name '.DirIcon' -type f | head -1)
              if [ -n "$icon_file" ]; then
                local ext
                ext=$(echo "$icon_file" | sed 's/.*\.//')
                [ "$ext" = "DirIcon" ] && ext="png"
                cp "$icon_file" "$ICON_DIR/$slug.$ext"
                icon="$ICON_DIR/$slug.$ext"
              fi
            fi

            rm -rf "$tmpdir"

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

          remove_entry() {
            local filename="$1"
            local icon_name
            icon_name=$(echo "$filename" | sed 's/\.AppImage$//; s/\.appimage$//')
            rm -f "$DESKTOP_DIR/appimage-$filename.desktop"
            rm -f "$ICON_DIR/$icon_name".*
          }

          # Remove our appimage-* entries when the app has registered its own
          cleanup_duplicates() {
            for desktop_file in "$DESKTOP_DIR"/appimage-*.desktop; do
              [ -f "$desktop_file" ] || continue
              local exec_path
              exec_path=$(sed -n 's/^Exec=//p' "$desktop_file" | head -1)
              [ -z "$exec_path" ] && continue
              local other
              other=$(grep -rl "$exec_path" "$DESKTOP_DIR"/ 2>/dev/null | grep -v "^$DESKTOP_DIR/appimage-" | head -1)
              if [ -n "$other" ]; then
                local bname
                bname=$(basename "$desktop_file" .desktop | sed 's/^appimage-//')
                rm -f "$desktop_file"
                local icon_name
                icon_name=$(echo "$bname" | sed 's/\.AppImage$//; s/\.appimage$//')
                rm -f "$ICON_DIR/$icon_name".*
              fi
            done
          }

          # Generate entries for existing AppImages
          find "$DIR" -maxdepth 1 -iname '*.appimage' -type f | while read -r f; do
            generate_entry "$f"
          done

          # Clean up stale entries and duplicates
          for desktop_file in "$DESKTOP_DIR"/appimage-*.desktop; do
            [ -f "$desktop_file" ] || continue
            appimage_name=$(basename "$desktop_file" .desktop | sed 's/^appimage-//')
            [ -f "$DIR/$appimage_name" ] || rm -f "$desktop_file"
          done
          cleanup_duplicates

          # Watch both ~/Applications and ~/.local/share/applications
          inotifywait -m -e create -e moved_to -e delete -e moved_from \
            "$DIR" "$DESKTOP_DIR" --format '%w|%e|%f' | while IFS='|' read -r watched_dir event filename; do
            if [ "$watched_dir" = "$DIR/" ]; then
              case "$filename" in
                *.AppImage|*.appimage)
                  case "$event" in
                    *DELETE*|*MOVED_FROM*)
                      remove_entry "$filename"
                      ;;
                    *)
                      generate_entry "$DIR/$filename"
                      ;;
                  esac
                  ;;
              esac
            elif [ "$watched_dir" = "$DESKTOP_DIR/" ]; then
              # App registered its own desktop entry — remove our duplicate
              case "$filename" in
                appimage-*) ;;
                *.desktop) cleanup_duplicates ;;
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
