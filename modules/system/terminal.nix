# Terminal Shell Configuration (System-level)
#
# This module enables Fish shell at the system level.
#
# Why system-level:
# - Makes Fish available as a login shell
# - Required for users.users.*.shell = pkgs.fish
#
# User-level configuration:
# - See home-manager/programs/fish.nix for shell customization
# - Aliases, functions, plugins, prompt are configured there
#
# Note: This only enables Fish system-wide, it doesn't configure it.

{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Fish at system level (used as login shell)
  programs.fish.enable = true;

  # Install kitty's xterm-kitty terminfo on headless hosts.
  #
  # Headless hosts are administered over SSH from kitty clients, which send
  # TERM=xterm-kitty. The host has no kitty of its own, so without the
  # terminfo the remote tmux auto-start (home-manager/programs/fish.nix) aborts
  # with "missing or unsuitable terminal: xterm-kitty". Install only that
  # terminfo so remote tmux starts with a plain (no-tmux) kitty session. This
  # is headless-only; a desktop kitty carries its own terminfo.
  environment.systemPackages = lib.mkIf (config.features.hardware.formFactor == "headless") [
    pkgs.kitty.terminfo
  ];
}
