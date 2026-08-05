{ lib, fetchzip, stdenvNoCC }:

stdenvNoCC.mkDerivation {
  pname = "css-loader-decky-plugin";
  version = "2.1.2";

  src = fetchzip {
    url = "https://github.com/DeckThemes/SDH-CssLoader/releases/download/v2.1.2/SDH-CSSLoader-Decky.zip";
    hash = "sha256-yBasWiInsHtN/rm2bJx7Tj7HCTH66CWSh/85E7YjHak=";
    stripRoot = false;
  };

  installPhase = ''
    mkdir -p $out
    cp -r SDH-CssLoader/* $out/
  '';

  meta = {
    description = "CSS Loader plugin for Decky Loader";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
  };
}
