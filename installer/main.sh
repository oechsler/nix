# shellcheck shell=bash
# Top-level installer orchestration.

main() {
  phase_validate
  load_state
  phase_select_host
  if [[ "$IS_LIVE" != true && "$INSTALLER_ISO" != true ]]; then
    echo -e "    ${DIM}Pulls the latest configuration from git and rebuilds the system.${RESET}"
    echo -e "    ${DIM}Activates immediately — no reboot required.${RESET}"
    echo ""
    if [[ "$YES" == true ]]; then
      phase_upgrade
      exit 0
    fi
    local confirm
    read -r -p "Run upgrade now? [Y/n]: " confirm
    echo ""
    [[ ! "$confirm" =~ ^[nN]$ ]] || exit 0
    phase_upgrade
    exit 0
  fi
  # shellcheck disable=SC2046
  echo -e "    Steps: ${BOLD}$(printf '%s ' $([[ "$DO_FORMAT" == true ]] && echo "format") $([[ "$DO_INSTALL" == true ]] && echo "install") $([[ "$DO_POST_INSTALL" == true ]] && echo "post-install"))${RESET}"
  echo ""
  phase_detect_features
  apply_keyboard_layout
  phase_collect_inputs
  phase_summary
  if [[ "$DO_FORMAT" != true && ("$DO_INSTALL" == true || "$DO_POST_INSTALL" == true) ]] && ! mountpoint -q /mnt 2>/dev/null; then
    DO_MOUNT=true
  fi
  STEP_TOTAL=0
  [[ "$DO_FORMAT" == true ]] && STEP_TOTAL=$((STEP_TOTAL + 1))
  [[ "$DO_MOUNT" == true ]] && STEP_TOTAL=$((STEP_TOTAL + 1))
  if [[ "$DO_INSTALL" == true ]]; then
    STEP_TOTAL=$((STEP_TOTAL + 1))
    [[ "$INSTALLER_ISO" != true ]] && STEP_TOTAL=$((STEP_TOTAL + 1))
  fi
  [[ "$DO_POST_INSTALL" == true ]] && STEP_TOTAL=$((STEP_TOTAL + 1))
  if [[ "$DO_FORMAT" == true ]]; then
    step "Partitioning disks"
    phase_partition
  elif [[ "$DO_MOUNT" == true ]]; then
    step "Mounting existing disks"
    phase_mount
  fi
  if [[ "$DO_INSTALL" == true ]]; then
    [[ "$INSTALLER_ISO" != true ]] && step "Detecting NixOS version"
    phase_state_version
    step "Installing NixOS"
    phase_install
  fi
  if [[ "$DO_POST_INSTALL" == true ]]; then
    step "Post-install setup"
    phase_post_install
  fi
  phase_complete
}
