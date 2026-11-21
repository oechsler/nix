{ pkgs }:

# Track Proton's stable Linux package while nixpkgs catches up with releases.
let
  version = "1.44.0";
in
pkgs.proton-pass.overrideAttrs (_previous: {
  inherit version;
  src = pkgs.fetchurl {
    name = "proton-pass_${version}_amd64.deb";
    url = "https://proton.me/download/pass/linux/proton-pass_${version}_amd64.deb";
    hash = "sha256-oAxRq5JZUlI4BPJC+CDSWklOEJu9OrVp7j2v5HbQnFE=";
  };
})
