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

{
  config,
  pkgs,
  lib,
  serviceLog,
  ...
}:

let
  userHome = config.users.users.${config.user.name}.home;
  capitalize =
    value:
    (lib.toUpper (builtins.substring 0 1 value))
    + (builtins.substring 1 (builtins.stringLength value) value);
  colorSchemeId = "Catppuccin${capitalize config.theme.catppuccin.flavor}${capitalize config.theme.catppuccin.accent}";
  translate = english: german: if lib.hasPrefix "de" config.locale.language then german else english;
  appImageAddedTitle = translate "AppImage added" "AppImage hinzugefügt";
  appImageRemovedTitle = translate "AppImage removed" "AppImage entfernt";
  appImageWatcherName = "AppImage";
  flatpakInstalledTitle = translate "Flatpak installed" "Flatpak installiert";
  flatpakRemovedTitle = translate "Flatpak removed" "Flatpak entfernt";
  flatpakWatcherName = "Flatpak";
  packageIcon = "${config.theme.icons.package}/share/icons/Papirus/32x32/mimetypes/package-x-generic.svg";
  flatpakNotify = pkgs.writeShellScript "flatpak-qt-theme-notify" ''
    ${pkgs.systemd}/bin/systemd-run --machine=${config.user.name}@ \
      --user --pipe --quiet --collect \
      ${pkgs.libnotify}/bin/notify-send "$@"
  '';
  flatpakTransactionWait = ''
    transaction_ready=false
    transaction_wait_logged=false
    previous_apps=""
    previous_tree_mtime=""
    stable_checks=0
    for attempt in $(seq 1 300); do
      current_apps=$($FLATPAK list --system --app --columns=application,runtime)
      current_tree_mtime=$(${pkgs.coreutils}/bin/stat -c %Y /var/lib/flatpak)
      if ! ${pkgs.procps}/bin/pgrep -x flatpak >/dev/null 2>&1 \
        && [ "$current_apps" = "$previous_apps" ] \
        && [ "$current_tree_mtime" = "$previous_tree_mtime" ]; then
        stable_checks=$((stable_checks + 1))
      else
        stable_checks=0
      fi
      previous_apps="$current_apps"
      previous_tree_mtime="$current_tree_mtime"
      if [ "$stable_checks" -ge 3 ]; then
        transaction_ready=true
        log transaction ready "attempt=$attempt"
        break
      fi
      if [ "$transaction_wait_logged" != true ]; then
        log transaction waiting ""
        transaction_wait_logged=true
      fi
      ${pkgs.coreutils}/bin/sleep 2
    done
    if [ "$transaction_ready" != true ]; then
      log transaction error "timeout=600s"
      exit 1
    fi
  '';
  flatpakQtThemeOverrides = ''
    set -euo pipefail
    ${serviceLog}
    log sync started "scheme=${colorSchemeId} config=${userHome}/.config/kdeglobals data=${userHome}/.local/share"
    # Flatpak deploys apps and extensions in separate steps. Wait for both the
    # client transaction and the installed state to settle before scanning.
    ${flatpakTransactionWait}

    $FLATPAK override --system --unset-env=QT_QPA_PLATFORMTHEME
    $FLATPAK override --system --unset-env=XDG_CURRENT_DESKTOP
    $FLATPAK override --system --unset-env=KDE_FULL_SESSION
    $FLATPAK override --system --unset-env=KDE_SESSION_VERSION
    $FLATPAK override --system --unset-env=XDG_CONFIG_DIRS
    $FLATPAK override --system --unset-env=XDG_CONFIG_HOME
    kdeApps=0
    otherApps=0
    while IFS=$'\t' read -r app runtime; do
      [ -n "$app" ] || continue

      $FLATPAK override --system "$app" --unset-env=XDG_CONFIG_DIRS
      $FLATPAK override --system "$app" --unset-env=XDG_CONFIG_HOME
      $FLATPAK override --system "$app" --unset-env=XDG_CURRENT_DESKTOP
      $FLATPAK override --system "$app" --unset-env=KDE_FULL_SESSION
      $FLATPAK override --system "$app" --unset-env=KDE_SESSION_VERSION

      case "$runtime" in
        org.kde.Platform/*)
          kdeApps=$((kdeApps + 1))
          log apply started "app=$app runtime=$runtime"
          $FLATPAK override --system "$app" --env=QT_QPA_PLATFORMTHEME=kde
          $FLATPAK override --system "$app" --env=QT_QUICK_CONTROLS_STYLE=org.kde.desktop
          $FLATPAK override --system "$app" --env=QML2_IMPORT_PATH=/usr/lib/qml:/app/lib/qml
          $FLATPAK override --system "$app" --env=QT_PLUGIN_PATH=/usr/lib/plugins:/app/lib/plugins:/usr/share/runtime/lib/plugins
          $FLATPAK override --system "$app" --env=XDG_CONFIG_DIRS=${userHome}/.config:/app/etc/xdg:/etc/xdg
          $FLATPAK override --system "$app" --env=XDG_DATA_DIRS=${userHome}/.local/share:/app/share:/usr/share:/usr/share/runtime/share:/run/host/user-share:/run/host/share
          $FLATPAK override --system "$app" --env=KDE_COLOR_SCHEME=${colorSchemeId}
          $FLATPAK override --system "$app" --filesystem=xdg-config/kdeglobals:ro
          $FLATPAK override --system "$app" --filesystem=xdg-data/color-schemes:ro
          $FLATPAK override --system "$app" --filesystem=xdg-data/icons:ro
          $FLATPAK override --system "$app" --filesystem=xdg-data/themes:ro
          ;;
        *)
          otherApps=$((otherApps + 1))
          log cleanup started "app=$app runtime=$runtime"
          $FLATPAK override --system "$app" --unset-env=QT_QPA_PLATFORMTHEME
          $FLATPAK override --system "$app" --unset-env=QT_QUICK_CONTROLS_STYLE
          $FLATPAK override --system "$app" --unset-env=QML2_IMPORT_PATH
          $FLATPAK override --system "$app" --unset-env=QT_PLUGIN_PATH
          $FLATPAK override --system "$app" --unset-env=XDG_CONFIG_DIRS
          $FLATPAK override --system "$app" --unset-env=KDE_COLOR_SCHEME
          ;;
      esac
    done < <($FLATPAK list --system --app --columns=application,runtime)
    log sync ok "kde_apps=$kdeApps other_apps=$otherApps"
  '';
  flatpakWatcherScript = ''
    set -euo pipefail
    ${serviceLog}
    log sync started "state=/var/lib/flatpak-watcher/apps"

    ${flatpakTransactionWait}

    resolve_icon() {
      local app="$1"
      local icon_name="$app"
      local desktop_file="/var/lib/flatpak/exports/share/applications/$app.desktop"
      if [ -f "$desktop_file" ]; then
        icon_name=$(${pkgs.gnused}/bin/sed -n 's/^Icon=//p' "$desktop_file" | ${pkgs.coreutils}/bin/head -1)
        icon_name=$(${pkgs.coreutils}/bin/basename "$icon_name")
        icon_name="''${icon_name%.png}"
        icon_name="''${icon_name%.svg}"
        icon_name="''${icon_name%.xpm}"
      fi
      for icon_root in "${config.theme.icons.package}/share/icons/Papirus" "/var/lib/flatpak/exports/share/icons/hicolor"; do
        for size in 32x32 48x48 64x64 24x24 scalable 128x128 96x96; do
          for extension in svg png; do
            candidate="$icon_root/$size/apps/$icon_name.$extension"
            if [ -f "$candidate" ]; then
              printf '%s\n' "$candidate"
              return 0
            fi
            done
          done
        done
      printf '%s\n' "${packageIcon}"
    }
    notification_id() {
      local checksum
      checksum=$(${pkgs.coreutils}/bin/cksum <<< "$1" | ${pkgs.coreutils}/bin/cut -d' ' -f1)
      printf '%s\n' "$((checksum % 2000000000 + 10000))"
    }

    state_dir=/var/lib/flatpak-watcher
    previous_state="$state_dir/apps"
    current_state=$(mktemp)
    install -d -m 0755 "$state_dir"
    $FLATPAK list --system --app --columns=application,name,runtime | sort > "$current_state"
    if [ -f "$previous_state" ]; then
      while IFS=$'\t' read -r app name runtime; do
        [ -n "$app" ] || continue
        if ! cut -f1 "$previous_state" | grep -Fqx "$app"; then
          icon=$(resolve_icon "$app")
          log app installed "app=$app runtime=$runtime"
          log icon resolved "app=$app path=$icon"
          ${flatpakNotify} -a "${flatpakWatcherName}" -i "$icon" \
            --replace-id="$(notification_id "$app")" \
            "${flatpakInstalledTitle}" "$name" || true
        fi
      done < "$current_state"
      while IFS=$'\t' read -r app name runtime; do
        [ -n "$app" ] || continue
        if ! cut -f1 "$current_state" | grep -Fqx "$app"; then
          log app removed "app=$app runtime=$runtime"
          icon=$(resolve_icon "$app")
          log icon resolved "app=$app path=$icon"
          ${flatpakNotify} -a "${flatpakWatcherName}" -i "$icon" \
            --replace-id="$(notification_id "$app")" \
            "${flatpakRemovedTitle}" "$name" || true
        fi
      done < "$previous_state"
    else
      log app baseline "apps=$(wc -l < "$current_state")"
    fi
    mv "$current_state" "$previous_state"
    log sync ok "apps=$(wc -l < "$previous_state")"
  '';
in
{
  #===========================
  # Options
  #===========================

  options.features = {
    flatpak.enable = (lib.mkEnableOption "Flatpak support") // {
      default = true;
    };
    appimage.enable = (lib.mkEnableOption "AppImage support") // {
      default = true;
    };
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
        remotes = [
          {
            name = "flathub";
            location = "https://flathub.org/repo/flathub.flatpakrepo";
          }
        ];

        # Pre-installed Flatpaks
        packages = [
          "com.github.tchx84.Flatseal" # Flatpak permission manager
          "io.github.flattool.Warehouse" # Flatpak manager with cleanup (replaces flatsweep)
          "org.fedoraproject.MediaWriter" # Fedora Media Writer for bootable USB drives
        ];
      };

      # Apply the minimal Qt theme integration after declarative apps exist.
      systemd = {
        services.flatpak-qt-theme = {
          description = "Apply runtime-specific Flatpak Qt theme overrides";
          wantedBy = [ "graphical.target" ];
          after = [ "flatpak-managed-install.service" ];
          wants = [ "flatpak-managed-install.service" ];
          serviceConfig.Type = "oneshot";
          script = ''
            FLATPAK="${pkgs.flatpak}/bin/flatpak"
            if [ -x "$FLATPAK" ]; then
              ${flatpakQtThemeOverrides}
            fi
          '';
        };
        paths.flatpak-qt-theme = {
          description = "Watch system Flatpak installations for theme updates";
          wantedBy = [ "multi-user.target" ];
          after = [ "var-lib-flatpak.mount" ];
          pathConfig = {
            PathChanged = [
              "/var/lib/flatpak"
              "/var/lib/flatpak/app"
              "/var/lib/flatpak/runtime"
            ];
            Unit = "flatpak-qt-theme.service";
          };
        };
        services.flatpak-watcher = {
          description = "Notify about system Flatpak installations";
          wantedBy = [ "graphical.target" ];
          after = [ "flatpak-managed-install.service" ];
          wants = [ "flatpak-managed-install.service" ];
          serviceConfig.Type = "oneshot";
          script = ''
            FLATPAK="${pkgs.flatpak}/bin/flatpak"
            if [ -x "$FLATPAK" ]; then
              ${flatpakWatcherScript}
            fi
          '';
        };
        paths.flatpak-watcher = {
          description = "Watch system Flatpak installations for notifications";
          wantedBy = [ "multi-user.target" ];
          after = [ "var-lib-flatpak.mount" ];
          pathConfig = {
            PathChanged = [
              "/var/lib/flatpak"
              "/var/lib/flatpak/app"
              "/var/lib/flatpak/runtime"
            ];
            Unit = "flatpak-watcher.service";
          };
        };
      };

      # Make Flatpak apps visible in application launchers
      environment.sessionVariables.XDG_DATA_DIRS = [ "/var/lib/flatpak/exports/share" ];

      # Flatpak GUI managers (KDE uses Discover, others use GNOME Software)
      environment.systemPackages = lib.mkIf (config.features.desktop.wm != "kde") (
        with pkgs;
        [
          gnome-software
        ]
      );
    })

    #---------------------------
    # 2. AppImage Support
    #---------------------------
    (lib.mkIf config.features.appimage.enable {
      # Enable AppImage execution via binfmt
      programs.appimage = {
        enable = true;
        binfmt = true; # Allows running AppImages without chmod +x
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
        path = with pkgs; [
          inotify-tools
          uutils-coreutils-noprefix
          findutils
          gnused
          squashfsTools
        ];

        script = ''
                    ${serviceLog}
                    notification_id() {
                      local checksum
                      checksum=$(${pkgs.coreutils}/bin/cksum <<< "$1" | ${pkgs.coreutils}/bin/cut -d' ' -f1)
                      printf '%s\n' "$((checksum % 2000000000 + 10000))"
                    }

                    # Directories
                    DIR="$HOME/Applications"                         # Where AppImages are stored
                    DESKTOP_DIR="$HOME/.local/share/applications"    # Desktop entries
                    ICON_DIR="$HOME/.local/share/icons/appimage"     # Extracted icons
                    mkdir -p "$DIR" "$DESKTOP_DIR" "$ICON_DIR"
                    log watch started "directories=$DIR,$DESKTOP_DIR"

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
                      log process started "file=$appimage"
                      if [ ! -f "$appimage" ]; then
                        log process skipped "reason=missing file=$appimage"
                        return
                      fi
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
                        log process skipped "reason=already-registered-by:$existing"
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
                      else
                        log extract warning "reason=no-squashfs file=$appimage"
                      fi

                      # Extract application name from embedded .desktop file
                      local name=""
                      local embedded_desktop
                      embedded_desktop=$(find "$tmpdir/root" -maxdepth 1 -name '*.desktop' -type f 2>/dev/null | head -1)
                      local icon_id=""
                      if [ -n "$embedded_desktop" ]; then
                        name=$(sed -n 's/^Name=//p' "$embedded_desktop" | head -1)
                        icon_id=$(sed -n 's/^Icon=//p' "$embedded_desktop" | head -1)
                        icon_id=$(basename "$icon_id")
                        icon_id="''${icon_id%.png}"
                        icon_id="''${icon_id%.svg}"
                        icon_id="''${icon_id%.xpm}"
                      fi
                      # Fallback: Generate name from filename (e.g., "my-app-1.2.3" → "my app 1.2.3")
                      [ -z "$name" ] && name=$(echo "$slug" | sed 's/-/ /g; s/_/ /g')

                      # Extract and install icon
                      local icon="${packageIcon}"  # Guaranteed host fallback icon
                      if [ -d "$tmpdir/root" ]; then
                        local icon_file
                        # Prefer the icon named by the embedded desktop file.
                        if [ -n "$icon_id" ]; then
                          local icon_path
                          icon_path=$(unsquashfs -ll -offset "$offset" "$appimage" 2>/dev/null | while IFS= read -r line; do
                            case "$line" in
                              -*squashfs-root/*"$icon_id".png|-*squashfs-root/*"$icon_id".svg)
                                path="''${line#*squashfs-root/}"
                                path="''${path%% ->*}"
                                printf '%s\n' "$path"
                                break
                                ;;
                            esac
                          done | head -1)
                          if [ -n "$icon_path" ]; then
                            local icon_ext="''${icon_path##*.}"
                            icon_file="$tmpdir/icon.$icon_ext"
                            unsquashfs -cat -offset "$offset" "$appimage" "$icon_path" > "$icon_file" 2>/dev/null || icon_file=""
                          fi
                        fi
                        # Fallback: look for any extracted PNG or SVG icon.
                        [ -z "$icon_file" ] && icon_file=$(find "$tmpdir/root" -type f \( -name '*.png' -o -name '*.svg' \) | head -1)
                        # Fallback: .DirIcon (common in AppImages)
                        [ -z "$icon_file" ] && icon_file=$(find "$tmpdir/root" -maxdepth 1 -name '.DirIcon' -type f | head -1)

                        if [ -n "$icon_file" ]; then
                          local ext
                          ext=$(echo "$icon_file" | sed 's/.*\.//')
                          [ "$ext" = "DirIcon" ] && ext="png"
                          # Copy icon to our icon directory
                          cp "$icon_file" "$ICON_DIR/$slug.$ext"
                          icon="$ICON_DIR/$slug.$ext"
                        else
                          log icon fallback "file=$basename_file icon=$icon"
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
                      log register ok "file=$basename_file desktop=$desktop_file"
                      ${pkgs.libnotify}/bin/notify-send -a "${appImageWatcherName}" -i "''${icon}" \
                        --replace-id="$(notification_id "$basename_file")" \
                        "${appImageAddedTitle}" "$name" || true
                    }

                    # Function: Remove desktop entry when AppImage is deleted
                    #
                    # Args:
                    #   $1 = basename of .AppImage file (e.g., "app.AppImage")
                    remove_entry() {
                      local filename="$1"
                      log remove started "file=$filename"
                      local icon_name
                      icon_name=$(echo "$filename" | sed 's/\.AppImage$//; s/\.appimage$//')
                      local removed_icon="${packageIcon}"
                      for extension in svg png; do
                        if [ -f "$ICON_DIR/$icon_name.$extension" ]; then
                          removed_icon="$ICON_DIR/$icon_name.$extension"
                          break
                        fi
                      done
                      rm -f "$DESKTOP_DIR/appimage-$filename.desktop"
                      rm -f "$ICON_DIR/$icon_name".*
                      ${pkgs.libnotify}/bin/notify-send -a "${appImageWatcherName}" -i "$removed_icon" \
                        --replace-id="$(notification_id "$filename")" \
                        "${appImageRemovedTitle}" "$icon_name" || true
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
                    log scan started "directory=$DIR"
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
                      log event received "event=$event path=$watched_dir$filename"

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
