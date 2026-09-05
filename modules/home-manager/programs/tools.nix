# Development Tools Configuration
#
# This module configures general CLI tools.
#
# Configuration:
# - GitHub CLI enabled
# - Git protocol: SSH (not HTTPS)
# - Git credential helper: Disabled (using git-credential-manager from git.nix)
# - Ouch for archive compression/extraction
#
# Usage:
#   gh pr create
#   gh issue list
#   gh repo clone owner/repo

{
  pkgs,
  lib,
  features,
  ...
}:

let
  useTuiManagement =
    features.hardware.formFactor == "headless"
    || (features.desktop.enable && features.desktop.wm == "hyprland");
in
{
  home.packages = [
    pkgs.ouch
  ]
  ++ lib.optionals (useTuiManagement && features.bluetooth.enable) [ pkgs.bluetui ]
  ++ lib.optionals (useTuiManagement && features.wifi.enable) [ pkgs.impala ]
  ++ lib.optionals (useTuiManagement && features.audio.enable) [ pkgs.wiremix ];

}
