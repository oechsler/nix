{ pkgs }:

# Spotify's official Debian release moves ahead of the Snap build in nixpkgs.
let
  version = "1.3.8.620.g39b276d5d7ac";
in
pkgs.spotify.overrideAttrs (previous: {
  inherit version;
  src = pkgs.fetchurl {
    name = "spotify-client-${version}_amd64.deb";
    url = "https://repository.spotify.com/pool/non-free/s/spotify-client/spotify-client_${version}_amd64.deb";
    hash = "sha256-NaDEAFnDecpq+XUFkYwn3/q0ZzktplteK1EnNIZYmnc=";
  };
  nativeBuildInputs = previous.nativeBuildInputs ++ [ pkgs.dpkg ];
  unpackPhase = ''
    runHook preUnpack
    ${pkgs.dpkg}/bin/dpkg-deb --extract "$src" .
    runHook postUnpack
  '';
})
