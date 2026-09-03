# Optional and supporting desktop components used by the Hyprland session.
{ features, lib, ... }:
{
  imports = [
    ./awww.nix
    ./automount.nix
    ./dunst.nix
    ./hypr-dock.nix
    ./hypridle.nix
    ./hyprlock.nix
    ./hyprmoncfg.nix
    ./hyprshell.nix
    ./rofi.nix
    ./theme.nix
    ./waybar.nix
  ]
  ++ lib.optionals (features.desktop.fileManager == "default") [
    ./nautilus.nix
  ];
}
