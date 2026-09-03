# Authentication module entry point.

{ ... }:

{
  imports = [
    ./auth/options.nix
    ./auth/ssh.nix
    ./auth/totp.nix
    ./auth/yubikey.nix
    ./auth/luks.nix
  ];
}
