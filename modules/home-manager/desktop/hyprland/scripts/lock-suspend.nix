# Lock and Suspend Script
#
# Locks the current session and waits for hyprlock to take over before
# suspending. Used by both hypridle and the Hyprland power menu.
{ pkgs }:

pkgs.writeShellScript "lock-and-suspend" ''
  set -eu

  ${pkgs.systemd}/bin/loginctl lock-session

  # Give hyprlock time to take over the display before suspending.
  for _ in $(${pkgs.coreutils}/bin/seq 1 100); do
    if ${pkgs.procps}/bin/pidof hyprlock > /dev/null; then
      ${pkgs.coreutils}/bin/sleep 1
      ${pkgs.systemd}/bin/systemctl suspend
      exit 0
    fi
    ${pkgs.coreutils}/bin/sleep 0.05
  done

  exit 1
''
