# Chromium/Electron Package Helpers
#
# Shared wrappers for Chromium-based desktop apps.

{ pkgs }:

{
  wrapHdrSdrApp =
    {
      package,
      binary,
      enable,
      name ? "${binary}-chromium-hdr-sdr",
    }:
    if enable then
      pkgs.symlinkJoin {
        inherit name;
        paths = [ package ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          rm -f "$out/bin/${binary}"
          makeWrapper "${package}/bin/${binary}" "$out/bin/${binary}" \
            --add-flags "--use-gl=egl"
        '';
      }
    else
      package;
}
