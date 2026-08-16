# Home Manager Maintenance
#
# Shared activation housekeeping for desktop home configurations.

{ lib, ... }:

{
  home.enableNixpkgsReleaseCheck = false;

  home.activation.cleanupBackups = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    rm -f ~/.gtkrc-2.0.bak
    rm -f ~/.config/gtk-4.0/gtk.css.bak ~/.config/gtk-4.0/gtk-dark.css.bak
    for f in ~/.local/share/themes/*.bak; do
      [ -e "$f" ] || continue
      chmod -R u+w "$f" 2>/dev/null || true
      rm -rf "$f"
    done
  '';
}
