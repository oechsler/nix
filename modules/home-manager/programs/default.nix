# User Programs Configuration
#
# This module imports all user-level program configurations:
# - apps.nix - Desktop applications (Discord, Spotify, etc.)
# - cinny.nix - Cinny Matrix client with Catppuccin userstyle
# - browsers.nix - Firefox configuration
# - development.nix - Development tools and languages
# - fish.nix - Fish shell configuration
# - git.nix - Git and SSH configuration
# - mangohud.nix - MangoHud gaming overlay (Catppuccin-themed)
# - neovim.nix - Neovim editor
# - opencode.nix - OpenCode AI coding agent configuration
# - proton-pass.nix - Proton Pass password manager and SSH agent
# - terminal.nix - Kitty terminal emulator
# - tmux.nix - Tmux terminal multiplexer
# - tools.nix - GitHub CLI

{
  imports = [
    ./apps.nix
    ./cinny.nix
    ./browsers.nix
    ./development.nix
    ./fish.nix
    ./git.nix
    ./kubernetes.nix
    ./lsp.nix
    ./mangohud.nix
    ./neovim.nix
    ./opencode.nix
    ./proton-pass.nix
    ./pvetui.nix
    ./terminal.nix
    ./tmux.nix
    ./tools.nix
  ];
}
