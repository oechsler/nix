{ lib, stdenvNoCC, fetchFromGitHub }:

stdenvNoCC.mkDerivation {
  pname = "catppuccin-deck";
  version = "1.1.3";

  src = fetchFromGitHub {
    owner = "catppuccin";
    repo = "steam-deck";
    rev = "v1.1.3";
    hash = "sha256-zAg+wwmkYjTjUS3f30hK+4M9ixIHVWiSsTydTOUeyNY=";
  };

  installPhase = ''
    runHook preInstall
    mkdir -p $out/flavors $out/tweaks
    cp src/theme.json src/shared.css src/svg.css src/keyboard.css $out/ || true
    cp src/flavors/*.css $out/flavors/ || true
    cp src/tweaks/*.css $out/tweaks/ || true
    runHook postInstall
  '';

  meta = {
    description = "Catppuccin theme for Steam Deck UI (CSS Loader)";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
