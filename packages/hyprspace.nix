{
  lib,
  gcc14Stdenv,
  hyprland,
  pkg-config,
  src,
}:
gcc14Stdenv.mkDerivation {
  pname = "Hyprspace";
  version = "unstable-2026-05-28";
  inherit src;

  nativeBuildInputs = [
    pkg-config
    gcc14Stdenv.cc
  ];

  buildInputs = [
    hyprland
  ];

  buildPhase = ''
    runHook preBuild
    make all CXX=${gcc14Stdenv.cc}/bin/g++
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib
    cp Hyprspace.so $out/lib/libHyprspace.so
    runHook postInstall
  '';

  meta = with lib; {
    description = "Workspace overview plugin for Hyprland";
    homepage = "https://github.com/KZDKM/Hyprspace";
    license = licenses.gpl2Only;
    platforms = platforms.linux;
  };
}
