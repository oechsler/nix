# Hyprland Home Manager module.
#
# The implementation is split by responsibility. Keep this entry point small
# so the public module path remains stable.
{ ... }:
{
  imports = [
    ./home.nix
    ./hyprland-config.nix
    ./module-imports.nix
  ];
}
