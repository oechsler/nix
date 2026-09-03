# Home Manager Maintenance
#
# Shared activation housekeeping for desktop home configurations.

{ lib, pkgs, ... }:

{
  home.enableNixpkgsReleaseCheck = false;

  home.activation.cleanupBackups = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    ${pkgs.coreutils}/bin/rm -f ~/.gtkrc-2.0.bak
    ${pkgs.coreutils}/bin/rm -f ~/.config/gtk-4.0/gtk.css.bak ~/.config/gtk-4.0/gtk-dark.css.bak
    for f in ~/.local/share/themes/*.bak; do
      [ -e "$f" ] || continue
      ${pkgs.coreutils}/bin/chmod -R u+w "$f" 2>/dev/null || true
      ${pkgs.coreutils}/bin/rm -rf "$f"
    done
  '';
}
