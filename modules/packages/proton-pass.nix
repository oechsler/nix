{ pkgs }:

# Track Proton's stable Linux package while nixpkgs catches up with releases.
let
  version = "1.44.1";
in
pkgs.proton-pass.overrideAttrs (_previous: {
  inherit version;
  src = pkgs.fetchurl {
    name = "proton-pass_${version}_amd64.deb";
    url = "https://proton.me/download/pass/linux/proton-pass_${version}_amd64.deb";
    hash = "sha256-sVAOd0rBYOFO8WL5CqKTyAkyev+aXKtODTivwfLCFag=";
  };
})
