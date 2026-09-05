# shellcheck shell=bash
# shellcheck disable=SC2034
# Summary and completion output.

phase_summary() {
  echo ""
  echo -e "${BOLD}============================================${RESET}"
  echo -e "${BOLD}  Installation Summary${RESET}"
  echo -e "${BOLD}============================================${RESET}"
  echo ""
  echo -e "    Host:           $HOST"
  echo -e "    Username:       $CONFIG_USERNAME"
  # shellcheck disable=SC2046
  echo -e "    Steps:          $(printf '%s ' $([[ "$DO_FORMAT" == true ]] && echo "format") $([[ "$DO_INSTALL" == true ]] && echo "install") $([[ "$DO_POST_INSTALL" == true ]] && echo "post-install"))"
  echo ""
  if [[ "$DO_FORMAT" == true ]]; then
    echo -e "    ${BOLD}Disk Setup:${RESET}"
    if [[ "$FEAT_ENCRYPTION" == "true" ]]; then
      echo -e "      Encryption:   LUKS (password set)"
    else
      echo -e "      Encryption:   none"
    fi
    echo -e "      Filesystem:   btrfs with subvolumes"
    if [[ "$FEAT_IMPERMANENCE" == "true" ]]; then
      echo -e "      Impermanence: enabled (persist: $PERSIST_PREFIX)"
    else
      echo -e "      Impermanence: disabled"
    fi
    echo ""
  fi
  if [[ "$DO_POST_INSTALL" == true ]]; then
    echo -e "    ${BOLD}Post-Install:${RESET}"
    if [[ -n "$USER_PASSWORD_HASH" ]]; then
      echo -e "      Password:     will be written to config"
    elif [[ "$CONFIG_PASSWORD_LOCKED" == "false" ]]; then
      echo -e "      Password:     from sops (set at boot)"
    fi
    echo -e "      SSH key:      will be installed"
    echo -e "      SOPS:         age key from SSH key"
    if [[ "$FEAT_TOTP" == "true" ]]; then
      if [[ "$SKIP_TOTP" == "true" || "$YES" == "true" ]]; then
        echo -e "      TOTP 2FA:     deferred (run totp-init after first boot)"
      else
        echo -e "      TOTP 2FA:     will be configured interactively"
      fi
    fi
    [[ "$FEAT_YUBIKEY" == "true" ]] && echo -e "      YubiKey:      registration required after first boot"
    echo ""
  fi
  [[ "$DO_FORMAT" == true ]] && echo -e "    ${RED}${BOLD}WARNING: This will ERASE all data on the configured disks!${RESET}"
  echo ""
  if [[ "$DRY_RUN" == true ]]; then
    success "Dry-run complete. No changes were made."
    exit 0
  fi
  if [[ "$YES" != true ]]; then
    local confirm
    read -r -p "    Continue? [y/N]: " confirm
    [[ "$confirm" =~ ^[yY]$ ]] || {
      echo "Aborted."
      exit 0
    }
  fi
}

phase_complete() {
  INSTALL_SUCCESS=true
  local post_boot_tasks=() tpm_deferred=false oath_file="/mnt${PERSIST_PREFIX}/etc/users.oath"
  [[ "$FEAT_SECURE_BOOT" == "true" ]] && post_boot_tasks+=("secure-boot-init    — sign boot files and enroll Secure Boot keys")
  [[ "$FEAT_YUBIKEY_LUKS" == "true" && "$FEAT_ENCRYPTION" == "true" ]] && post_boot_tasks+=("yubikey-luks-init   — enroll YubiKey FIDO2 for LUKS unlock at boot")
  [[ "$FEAT_YUBIKEY" == "true" ]] && post_boot_tasks+=("yubikey-init        — register YubiKey for sudo / SSH")
  [[ "$FEAT_TOTP" == "true" && ! -f "$oath_file" ]] && post_boot_tasks+=("totp-init           — configure TOTP 2FA for sudo / SSH")
  if [[ "$TPM_ENROLLED" != "true" && "$FEAT_ENCRYPTION" == "true" && "$FEAT_UNLOCK_METHOD" == "tpm2" && ${#LUKS_DEVICES[@]} -gt 0 ]]; then
    tpm_deferred=true
    post_boot_tasks+=("tpm-luks-init       — enroll TPM2 for automatic LUKS unlock at boot")
  fi
  local board_vendor="" sys_vendor="" is_asus=false board_vendor_file=/sys/class/dmi/id/board_vendor sys_vendor_file=/sys/class/dmi/id/sys_vendor
  [[ -r "$board_vendor_file" ]] && board_vendor=$(<"$board_vendor_file")
  [[ -r "$sys_vendor_file" ]] && sys_vendor=$(<"$sys_vendor_file")
  if [[ "$board_vendor" == *"ASUSTeK"* || "$board_vendor" == *"ASUS"* || "$sys_vendor" == *"ASUSTeK"* || "$sys_vendor" == *"ASUS"* ]]; then
    is_asus=true
  fi
  echo ""
  echo -e "${BOLD}============================================${RESET}"
  echo -e "${GREEN}${BOLD}  Installation complete!${RESET}"
  echo -e "${BOLD}============================================${RESET}"
  echo ""
  echo -e "  ${BOLD}What was set up:${RESET}"
  echo ""
  echo -e "    NixOS installed for ${BOLD}$HOST${RESET} (${CONFIG_USERNAME})"
  if [[ "$FEAT_ENCRYPTION" == "true" ]]; then
    if [[ "$TPM_ENROLLED" == "true" ]]; then
      echo -e "    Disk encryption:  ${GREEN}LUKS + TPM2 auto-unlock${RESET}  ${DIM}(password fallback works)${RESET}"
    elif [[ "$FEAT_YUBIKEY_LUKS" == "true" ]]; then
      echo -e "    Disk encryption:  ${GREEN}LUKS${RESET}  ${DIM}(YubiKey FIDO2 enrollment pending — password at boot until then)${RESET}"
    elif [[ "$tpm_deferred" == "true" ]]; then
      echo -e "    Disk encryption:  ${GREEN}LUKS${RESET}  ${DIM}(TPM2 enrollment pending — password at boot until then)${RESET}"
    else
      echo -e "    Disk encryption:  ${GREEN}LUKS${RESET}  ${DIM}(password required at boot)${RESET}"
    fi
  fi
  if [[ "$FEAT_TOTP" == "true" ]]; then
    if [[ -f "$oath_file" ]]; then
      echo -e "    TOTP 2FA:         ${GREEN}configured${RESET}  ${DIM}(use your authenticator app for sudo/SSH)${RESET}"
    else
      echo -e "    TOTP 2FA:         ${YELLOW}pending${RESET}  ${DIM}(run totp-init after first boot)${RESET}"
    fi
  fi
  echo -e "    SSH key:          ${GREEN}installed${RESET}"
  echo -e "    SOPS age key:     ${GREEN}installed${RESET}"
  if [[ ${#post_boot_tasks[@]} -gt 0 ]]; then
    echo ""
    echo -e "  ${BOLD}${YELLOW}After first boot, run these commands:${RESET}"
    echo ""
    local i=1 task cmd desc
    for task in "${post_boot_tasks[@]}"; do
      cmd="${task%%—*}"
      desc="${task#*—}"
      echo -e "    ${BOLD}$((i++)).${RESET} ${BOLD}${cmd}${RESET} ${DIM}—${desc}${RESET}"
    done
    echo ""
    if [[ "$tpm_deferred" == "true" ]]; then
      echo -e "    ${DIM}Until TPM enrollment is complete, LUKS always requires the install password.${RESET}"
      if [[ "$FEAT_SECURE_BOOT" == "true" ]]; then
        echo -e "    ${DIM}Required order: 1. secure-boot-init, 2. tpm-luks-init.${RESET}"
        echo -e "    ${DIM}TPM enrollment seals against the active Secure Boot state (PCR 7).${RESET}"
      fi
    else
      echo -e "    ${DIM}Until enrolled: LUKS uses password, sudo uses password fallback.${RESET}"
    fi
  fi
  if [[ "$FEAT_SECURE_BOOT" == "true" ]]; then
    echo ""
    echo -e "  ${BOLD}Secure Boot — UEFI steps before running secure-boot-init:${RESET}"
    echo ""
    echo -e "    ${DIM}NixOS will boot normally with Secure Boot OFF until you complete these steps.${RESET}"
    echo ""
    if [[ "$is_asus" == "true" ]]; then
      echo -e "    ${YELLOW}! ASUS board — special Setup Mode procedure required.${RESET}"
      echo ""
      echo -e "    ${BOLD}Step A${RESET} — In UEFI (Boot → Secure Boot):"
      echo -e "      OS Type:          ${BOLD}Other OS${RESET}"
      echo -e "      Secure Boot Mode: ${BOLD}Custom${RESET}"
      echo -e "      Key Management:   ${BOLD}Clear Secure Boot Keys${RESET}"
      echo -e "      ${DIM}(ASUS does not enter Setup Mode automatically — key deletion is required)${RESET}"
      echo ""
      echo -e "    ${BOLD}Step B${RESET} — Save, reboot into NixOS and run ${BOLD}secure-boot-init${RESET}"
      echo ""
      echo -e "    ${BOLD}Step C${RESET} — In UEFI: activate Secure Boot:"
      echo -e "      Secure Boot: ${BOLD}Enabled${RESET}"
      echo -e "      ${DIM}→ Secure Boot state will show: On${RESET}"
    else
      echo -e "    ${BOLD}Step A${RESET} — In UEFI: enter Setup Mode:"
      echo -e "      Disable Secure Boot"
      echo -e "      Enable ${BOLD}Setup Mode${RESET}  ${DIM}(or 'Reset to Setup Mode' — clears existing keys)${RESET}"
      echo -e "      Save and reboot into NixOS"
      echo ""
      echo -e "    ${BOLD}Step B${RESET} — Run ${BOLD}secure-boot-init${RESET}"
      echo -e "      ${DIM}Generates keys, rebuilds with lanzaboote, enrolls into firmware.${RESET}"
      echo ""
      echo -e "    ${BOLD}Step C${RESET} — In UEFI: enable ${BOLD}Secure Boot${RESET}"
      echo -e "      ${DIM}Then run secure-boot-init once more to verify all files are signed.${RESET}"
    fi
  fi
  echo ""
  echo -e "${BOLD}============================================${RESET}"
  echo ""
  if [[ "$YES" != true ]]; then
    local confirm
    if [[ "$FEAT_SECURE_BOOT" == "true" ]]; then
      read -r -p "    Reboot into UEFI firmware setup now? [Y/n]: " confirm
      if [[ ! "${confirm:-}" =~ ^[nN]$ ]]; then
        systemctl reboot --firmware-setup
      else
        echo "    Reboot manually when ready."
      fi
    else
      read -r -p "    Reboot now? [Y/n]: " confirm
      [[ "${confirm:-}" =~ ^[nN]$ ]] || reboot
    fi
  fi
  echo ""
}
