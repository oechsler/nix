{ lib, buildGoModule, fetchFromGitHub, pkg-config, gtk3, gtk-layer-shell
, wrapGAppsHook3, librsvg, shared-mime-info }:

buildGoModule rec {
  pname = "hypr-dock";
  version = "1.1.1";

  src = fetchFromGitHub {
    owner = "lotos-linux";
    repo = "hypr-dock";
    rev = "v${version}";
    hash = "sha256-6YfjfSx26d1FSVHapoGqm6Yc1Wf/6e11IKR46pUTg5k=";
  };

  vendorHash = "sha256-X/0dJzJQ9xaS+oXOqltvMXh8eSS7MAkINBxf22+jUDg=";

  nativeBuildInputs = [ pkg-config wrapGAppsHook3 shared-mime-info ];
  buildInputs = [ gtk3 gtk-layer-shell librsvg ];

  subPackages = [ "main" ];

  postInstall = ''
    mv $out/bin/main $out/bin/hypr-dock

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
