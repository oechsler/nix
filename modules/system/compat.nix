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