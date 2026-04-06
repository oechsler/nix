{ lib, buildGoModule, fetchFromGitHub, pkg-config, gtk3, gtk-layer-shell
, wrapGAppsHook3, librsvg, shared-mime-info }:

buildGoModule rec {
  pname = "hypr-dock";
  version = "1.2.1";

  src = fetchFromGitHub {
    owner = "lotos-linux";
    repo = "hypr-dock";
    rev = "v${version}";
    hash = "sha256-78vecDP4Bx9974C5+iFzI1L7na3wFaGSYWe8YsfRIzs=";
  };

  vendorHash = "sha256-amBAJW9oyCU53bxHh8MHR4Fj64VBUTzcEnWnvPlcZ7g=";

  nativeBuildInputs = [ pkg-config wrapGAppsHook3 shared-mime-info ];
  buildInputs = [ gtk3 gtk-layer-shell librsvg ];

  subPackages = [ "cmd/hypr-dock" ];

  postInstall = ''
    mkdir -p $out/share/hypr-dock
    cp -r $src/configs/* $out/share/hypr-dock/
  '';

  meta = {
    description = "Interactive dock panel for Hyprland";
    homepage = "https://github.com/lotos-linux/hypr-dock";
    license = lib.licenses.gpl3Only;
    mainProgram = "hypr-dock";
  };
}
