#!/usr/bin/env bash
# NixOS Interactive Installer
#
# The implementation is split into focused modules under installer/. The
# modules intentionally share the installer state to preserve the original
# execution flow and CLI behavior.

# shellcheck disable=SC1091
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_DIR="$SCRIPT_DIR/installer"
# State consumed by the sourced installer phases.
# shellcheck disable=SC2034
ORIGINAL_ARGS=("$@")

source "$INSTALLER_DIR/context.sh"
source "$INSTALLER_DIR/output.sh"
source "$INSTALLER_DIR/cli.sh"
source "$INSTALLER_DIR/environment.sh"
source "$INSTALLER_DIR/features.sh"
source "$INSTALLER_DIR/inputs.sh"
source "$INSTALLER_DIR/output-phases.sh"
source "$INSTALLER_DIR/partition.sh"
source "$INSTALLER_DIR/install-phase.sh"
source "$INSTALLER_DIR/post-install.sh"
source "$INSTALLER_DIR/upgrade.sh"
source "$INSTALLER_DIR/main.sh"

parse_args "$@"
main "$@"
