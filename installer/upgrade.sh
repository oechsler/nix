# shellcheck shell=bash
# shellcheck disable=SC2034
# Installed-system upgrade flow and pending setup reporting.

show_pending_setup() {
  local json
  if [[ "$INSTALLER_ISO" == true ]]; then
    json=$(jq -c --arg host "$HOST" '.hosts[$host] // empty' "$ISO_MANIFEST")
  else
    json=$(nix eval --json "$REPO_DIR#nixosConfigurations.${HOST}.config" --apply '
    cfg: {
      secureBoot = cfg.features.secureBoot.enable;
      yubikey = cfg.features.auth.yubikey.enable;
      yubikeyLuks = cfg.features.encryption.unlockMethod == "yubikey";
      totp = cfg.features.auth.totp.enable;
      encryption = cfg.features.encryption.enable;
      unlockMethod = cfg.features.encryption.unlockMethod;
      persistPrefix = cfg.features.impermanence.persistPrefix;
    }
    ' 2>/dev/null) || error "Failed to evaluate setup status. Check flake syntax."
  fi
  local feat_sb feat_yubikey feat_yubikey_luks feat_totp feat_enc feat_unlock_method persist_prefix
  feat_sb=$(jq -r '.secureBoot // false' <<<"$json")
  feat_yubikey=$(jq -r '.yubikey // false' <<<"$json")
  feat_yubikey_luks=$(jq -r '.yubikeyLuks // false' <<<"$json")
  feat_totp=$(jq -r '.totp // false' <<<"$json")
  feat_enc=$(jq -r '.encryption // false' <<<"$json")
  feat_unlock_method=$(jq -r '.unlockMethod // "password"' <<<"$json")
  persist_prefix=$(jq -r '.persistPrefix // ""' <<<"$json")
  local sb_active=false yubikey_luks_enrolled=false yubikey_pam_enrolled=false totp_enrolled=false invoking_username="${SUDO_USER:-$USER}"
  if [[ "$feat_sb" == "true" ]]; then
    local sb_state
    sb_state=$(bootctl status 2>/dev/null | awk '/Secure Boot:/{print $3}')
    [[ "$sb_state" == "enabled" ]] && sb_active=true
  fi
  if [[ "$feat_yubikey_luks" == "true" && "$feat_enc" == "true" ]]; then
    local first_dev
    first_dev=$(lsblk -rno NAME,TYPE,PKNAME | awk '$2=="crypt" && $3!="" {print "/dev/"$3; exit}')
    [[ -n "$first_dev" ]] && systemd-cryptenroll "$first_dev" 2>/dev/null | grep -q "fido2" && yubikey_luks_enrolled=true
  fi
  local tpm_enrolled=false
  if [[ "$feat_unlock_method" == "tpm2" && "$feat_enc" == "true" ]]; then
    local tpm_first_dev
    tpm_first_dev=$(lsblk -rno NAME,TYPE,PKNAME | awk '$2=="crypt" && $3!="" {print "/dev/"$3; exit}')
    [[ -n "$tpm_first_dev" ]] && systemd-cryptenroll "$tpm_first_dev" 2>/dev/null | grep -q "tpm2" && tpm_enrolled=true
  fi
  if [[ "$feat_yubikey" == "true" ]]; then
    local u2f_file="${persist_prefix}/etc/u2f_mappings"
    [[ -f "$u2f_file" ]] && grep -q "^${invoking_username}:" "$u2f_file" 2>/dev/null && yubikey_pam_enrolled=true
  fi
  if [[ "$feat_totp" == "true" ]]; then
    local oath_file="${persist_prefix}/etc/users.oath"
    [[ -f "$oath_file" ]] && grep -q "^HOTP.*${invoking_username}" "$oath_file" 2>/dev/null && totp_enrolled=true
  fi
  local pending=()
  [[ "$feat_sb" == "true" && "$sb_active" != "true" ]] && pending+=("secure-boot-init    — sign boot files and enroll Secure Boot keys into firmware")
  [[ "$feat_yubikey_luks" == "true" && "$yubikey_luks_enrolled" != "true" ]] && pending+=("yubikey-luks-init   — enroll YubiKey FIDO2 for automatic disk unlock at boot")
  [[ "$feat_yubikey" == "true" && "$yubikey_pam_enrolled" != "true" ]] && pending+=("yubikey-init        — register YubiKey for sudo and SSH authentication")
  [[ "$feat_totp" == "true" && "$totp_enrolled" != "true" ]] && pending+=("totp-init           — set up TOTP two-factor authentication for sudo and SSH")
  [[ "$feat_unlock_method" == "tpm2" && "$feat_enc" == "true" && "$tpm_enrolled" != "true" ]] && pending+=("tpm-luks-init       — enroll TPM2 for automatic disk unlock at boot")
  if [[ ${#pending[@]} -eq 0 ]]; then success "All features are fully set up."; else
    echo -e "  ${BOLD}${YELLOW}Pending setup:${RESET}"
    echo ""
    local i=1 task cmd desc
    for task in "${pending[@]}"; do
      cmd="${task%%—*}"
      desc="${task#*—}"
      echo -e "    ${BOLD}$((i++)).${RESET} ${BOLD}${cmd}${RESET} ${DIM}—${desc}${RESET}"
    done
    echo ""
    echo -e "    ${DIM}Each script is interactive and guides you through the process step by step.${RESET}"
  fi
}

phase_upgrade() {
  local invoking_user="${SUDO_USER:-$USER}"
  for command_name in git sudo systemctl awk sed nixos-rebuild; do
    command -v "$command_name" &>/dev/null || error "Required command not found: $command_name"
  done
  info "Syncing repository..."
  echo ""
  if git -C "$REPO_DIR" remote get-url origin &>/dev/null; then
    sudo -u "$invoking_user" git -C "$REPO_DIR" checkout flake.lock
    sudo -u "$invoking_user" git -C "$REPO_DIR" pull --ff-only
    success "Repository up to date"
  else
    warn "No git remote configured — skipping pull"
  fi
  echo ""
  info "Rebuilding system..."
  echo ""
  if [[ "$REPAIR" == "true" ]]; then
    if [[ $EUID -eq 0 ]]; then
      info "Repairing Nix store before rebuild..."
      nix-store --verify --repair || true
    else
      warn "--repair requires root/trusted-user privileges; continuing without repair."
    fi
    echo ""
  fi
  local upgrade_was_active=false
  if systemctl is-active --quiet nixos-upgrade.timer 2>/dev/null || systemctl is-active --quiet nixos-upgrade.service 2>/dev/null; then
    upgrade_was_active=true
    if systemctl is-active --quiet nixos-upgrade.service 2>/dev/null; then
      info "nixos-upgrade.service is running — waiting for it to finish..."
      systemctl stop nixos-upgrade.service 2>/dev/null || true
      info "Verifying Nix store integrity..."
      nix-store --verify --repair 2>/dev/null || true
    fi
    info "Stopping nixos-upgrade.timer..."
    systemctl stop nixos-upgrade.timer 2>/dev/null || true
  fi
  local avail_gb max_jobs
  avail_gb=$(awk '/^MemAvailable:/{printf "%d", $2/1024/1024}' /proc/meminfo)
  max_jobs=$((avail_gb / 4))
  ((max_jobs < 1)) && max_jobs=1
  echo ""
  success "RAM available: ${avail_gb} GB — using --max-jobs ${max_jobs}"
  echo ""
  local sb_keys_exist=false sb_config_enabled=false host_config="$REPO_DIR/hosts/$HOST/configuration.nix"
  [[ -f /var/lib/sbctl/keys/db/db.pem && -f /var/lib/sbctl/keys/db/db.key ]] && sb_keys_exist=true
  grep -q 'secureBoot\.enable\s*=\s*true' "$host_config" 2>/dev/null && sb_config_enabled=true
  local rebuild_ok=true
  if [[ "$sb_config_enabled" == "true" && "$sb_keys_exist" != "true" ]]; then
    warn "Secure Boot keys not yet generated — disabling lanzaboote for this rebuild."
    echo ""
    local host_dir="$REPO_DIR/hosts/$HOST"
    local override_nix="$host_dir/secure-boot-upgrade-override.nix"
    SECURE_BOOT_OVERRIDE_FILE="$override_nix"
    SECURE_BOOT_CONFIG_FILE="$host_dir/configuration.nix"
    printf '{ lib, ... }: { features.secureBoot.enable = lib.mkForce false; }\n' >"$override_nix"
    sed -i "/imports = \[/a\\    ./secure-boot-upgrade-override.nix" "$host_dir/configuration.nix"
    git -C "$REPO_DIR" add "$override_nix" "$host_dir/configuration.nix"
    nixos-rebuild switch --flake "$REPO_DIR#$HOST" --max-jobs "$max_jobs" || rebuild_ok=false
    sed -i '/secure-boot-upgrade-override\.nix/d' "$host_dir/configuration.nix"
    rm -f "$override_nix"
    git -C "$REPO_DIR" rm --cached "$override_nix" 2>/dev/null || true
    git -C "$REPO_DIR" add "$host_dir/configuration.nix"
  else
    nixos-rebuild switch --flake "$REPO_DIR#$HOST" --max-jobs "$max_jobs" || rebuild_ok=false
  fi
  if [[ "$upgrade_was_active" == "true" ]]; then
    info "Restarting nixos-upgrade.timer..."
    systemctl start nixos-upgrade.timer
  fi
  [[ "$rebuild_ok" == true ]] || error "nixos-rebuild failed. Check the output above."
  echo ""
  success "System upgraded."
  [[ "$QUIET_UPGRADE" == "true" ]] && return
  echo ""
  echo -e "${BOLD}============================================${RESET}"
  echo -e "${GREEN}${BOLD}  Upgrade complete!${RESET}"
  echo -e "${BOLD}============================================${RESET}"
  echo ""
  show_pending_setup
  echo ""
  echo -e "${BOLD}============================================${RESET}"
  echo ""
}
