# Compatibility Layer Configuration
#
# This module enables nix-ld for running non-NixOS binaries.
#
# Problem:
# - Dynamically linked binaries expect libraries in /lib64, /usr/lib, etc.
# - NixOS stores libraries in /nix/store (different paths for each version)
# - Downloaded binaries, AppImages, etc. don't work out of the box
#
# Solution:
# - nix-ld provides a compatibility loader
# - Makes common libraries available to non-NixOS binaries
# - Covers: glibc, OpenSSL, zlib, curl, OpenGL, X11, fonts
#
# Use cases:
# - Downloaded binaries (GitHub releases, vendor tools)
# - AppImages (if not using appimage.enable)
# - Pre-built tools that aren't in nixpkgs

{ config, pkgs, ... }:

{
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc.lib
      glibc
      zlib
      openssl
      curl
      libGL
      libx11
      fontconfig
      freetype
    ];
  };
}