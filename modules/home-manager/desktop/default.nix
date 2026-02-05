{ features, lib, ... }:

{
  imports = lib.optionals features.desktop.enable (
    [
      ./theme.nix
      ./xdg.nix
      ./bookmarks.nix
      ./autostart.nix
      ./idle.nix
      ./displays.nix
    ]
    ++ lib.optionals (features.desktop.wm == "hyprland") [
      ./hyprland.nix
    ]
    ++ lib.optionals (features.desktop.wm == "kde") [
      ./dolphin.nix
    ]
  );
}
