# User Programs Configuration
#
# This module imports all user-level program configurations:
# - apps.nix - Desktop applications (Discord, Spotify, etc.)
# - browsers.nix - Firefox configuration
# - development.nix - Development tools and languages
# - fish.nix - Fish shell configuration
# - git.nix - Git and SSH configuration
# - neovim.nix - Neovim editor
# - terminal.nix - Kitty terminal emulator
# - tmux.nix - Tmux terminal multiplexer
# - tools.nix - GitHub CLI

{ ... }:

{
  imports = [
    ./apps.nix
    ./browsers.nix
    ./development.nix
    ./fish.nix
    ./git.nix
    ./neovim.nix
    ./terminal.nix
    ./tmux.nix
    ./tools.nix
  ];
}
