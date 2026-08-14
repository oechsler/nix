# Cinny Matrix Client
#
# Builds Cinny with the official Catppuccin userstyle embedded in the Tauri app.

{
  pkgs,
  lib,
  features,
  theme,
  ...
}:

let
  cinnyUserstyle = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/catppuccin/userstyles/main/styles/cinny/catppuccin.user.less";
    hash = "sha256-yOXRnkqN1ApnpOyfNRXcJdY9mKf0VrAFcZMAaHiXla8=";
  };
  cinnyCatppuccinLib = pkgs.fetchurl {
    url = "https://userstyles.catppuccin.com/lib/std/v1.less";
    hash = "sha256-XK9Oqan7Kz81DNyE3+ryl5sPi/OpvV+EkgL7WuLoGfM=";
  };
  cinnyStyle = pkgs.runCommand "cinny-catppuccin.css" { } ''
    cp ${cinnyUserstyle} style.less
    sed -i \
      -e '/^\/\* ==UserStyle==/,/^==\/UserStyle== \*\//d' \
      -e '/^@-moz-document domain("cinny.in") {/d' \
      -e '$d' \
      -e 's#https://userstyles.catppuccin.com/lib/lib.less#${cinnyCatppuccinLib}#' \
      -e '/https:\/\/prismjs.catppuccin.com\/variables.important.css/d' \
      -e 's/@lightFlavor/${theme.catppuccin.flavor}/g' \
      -e 's/@darkFlavor/${theme.catppuccin.flavor}/g' \
      -e 's/@accentColor/${theme.catppuccin.accent}/g' \
      style.less
    sed -i '1i @accentColor: ${theme.catppuccin.accent};' style.less
    ${pkgs.lessc}/bin/lessc style.less $out
  '';
  cinnyNotificationBridge = pkgs.writeText "cinny-notifications.js" ''
    (() => {
      const api = window.__TAURI__?.notification;
      if (!api) return;

      class CinnyNotification {
        static permission = "default";

        static requestPermission() {
          return api.isPermissionGranted().then((granted) => {
            if (granted) {
              CinnyNotification.permission = "granted";
              return "granted";
            }
            return api.requestPermission().then((permission) => {
              CinnyNotification.permission = permission;
              return permission;
            });
          });
        }

        constructor(title, options = {}) {
          this.title = title;
          this.body = options.body || "";
          this.onclick = null;
          this.onclose = null;
          this.onerror = null;
          this.onshow = null;

          CinnyNotification.requestPermission().then((permission) => {
            if (permission === "granted") {
              return api.sendNotification({ title: this.title, body: this.body });
            }
          });
        }

        close() {}
      }

      window.Notification = CinnyNotification;
    })();
  '';
  cinnyUnwrapped = pkgs.cinny.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      cp ${cinnyStyle} $out/catppuccin.css
      cp ${cinnyNotificationBridge} $out/cinny-notifications.js
      ${pkgs.gnused}/bin/sed -i \
        's#</head>#<script src="./cinny-notifications.js"></script><link rel="stylesheet" href="./catppuccin.css"></head>#' \
      $out/index.html
    '';
  });
  cinnyDesktop = pkgs.cinny-desktop.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      ${pkgs.jq}/bin/jq \
        --arg frontendDist "${cinnyUnwrapped}" \
        '.build.frontendDist = $frontendDist | .app.withGlobalTauri = true' \
        tauri.conf.json | ${pkgs.moreutils}/bin/sponge tauri.conf.json
      substituteInPlace src/lib.rs \
        --replace-fail '.plugin(tauri_plugin_dialog::init())' '.plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_notification::init())'
    '';
  });
in
{
  config = lib.mkIf features.apps.enable {
    home.packages = [ cinnyDesktop ];
  };
}
