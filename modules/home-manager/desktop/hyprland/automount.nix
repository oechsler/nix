# Hyprland removable media automount
#
# Udiskie handles removable media for the standalone Hyprland session. KDE
# uses Plasma's own removable-device settings and does not import this module.

{
  config,
  pkgs,
  i18n,
  lib,
  theme,
  ...
}:

let
  inherit (i18n) translate;
  mountedTitle = translate "Device mounted" "Datenträger eingehängt";
  mountedMessage = translate "was mounted" "wurde eingehängt";
  removableMedia = translate "Removable media" "Wechselmedium";
  iconPath = "${theme.icons.package}/share/icons/Papirus/32x32/devices/drive-removable-media-usb-pendrive.svg";

  notifyScript = pkgs.writeShellScript "udiskie-notify" ''
    event="$1"
    label="$2"
    drive_label="$3"

    label="''${label:-$drive_label}"
    label="''${label:-${removableMedia}}"

    case "$event" in
      device_mounted)
        ${pkgs.libnotify}/bin/notify-send \
          --app-name="udiskie" \
          --icon="${iconPath}" \
          "${mountedTitle}" \
          "$label ${mountedMessage}"
        ;;
    esac
  '';
in

{
  home.activation.udiskieRestart = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    systemctl --user --machine=${config.home.username}@ try-restart udiskie.service >/dev/null 2>&1 || true
  '';

  # Let udiskie own automounting instead of racing GVFS for the same device.
  dconf.settings."org/gnome/desktop/media-handling" = {
    automount = false;
    automount-open = false;
  };

  services.udiskie = {
    enable = true;
    automount = true;
    notify = false;
    tray = "never";
    settings.program_options.event_hook = [
      notifyScript
      "{event}"
      "{id_label}"
      "{drive_label}"
      "{mount_path}"
    ];
  };
}
