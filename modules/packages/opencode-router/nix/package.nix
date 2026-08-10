{
  pkgs,
  flakeRoot ? null,
}:

let
  rustSrc =
    if flakeRoot != null then
      builtins.path {
        path = flakeRoot + "/modules/packages/opencode-router/rust";
        name = "opencode-router-rust";
      }
    else
      builtins.path {
        path = ../rust;
        name = "opencode-router-rust";
      };

  opencodeRouter = pkgs.rustPlatform.buildRustPackage {
    pname = "opencode-router";
    version = "0.1.0";
    src = rustSrc;
    cargoLock.lockFile = "${rustSrc}/Cargo.lock";
  };

  routerImage = pkgs.dockerTools.buildLayeredImage {
    name = "opencode-router";
    tag = "latest";
    contents = [ opencodeRouter ];
    config = {
      Cmd = [
        "/bin/opencode-router"
        "--config"
        "/etc/opencode-router/config.toml"
      ];
      ExposedPorts = {
        "4000/tcp" = { };
      };
    };
  };
in
{
  package = opencodeRouter;
  image = routerImage;
}
