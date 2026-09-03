# shellcheck shell=bash
# shellcheck disable=SC2034
# Post-install provisioning.

setup_ssh() {
  AGE_KEY="$(nix-shell -p ssh-to-age --run "ssh-to-age -private-key -i $(printf '%q' "$SSH_KEY_FILE")")"
  local ssh_dir="/mnt/home/$CONFIG_USERNAME/.ssh"
  mkdir -p "$ssh_dir"
  cp "$SSH_KEY_FILE" "$ssh_dir/id_ed25519"
  ssh-keygen -y -f "$SSH_KEY_FILE" >"$ssh_dir/id_ed25519.pub"
  chmod 700 "$ssh_dir"
  chmod 600 "$ssh_dir/id_ed25519"
  chmod 644 "$ssh_dir/id_ed25519.pub"
  [[ -z "$SSH_KEY" ]] && rm -f "$SSH_KEY_FILE"
  success "SSH key installed"
}

setup_sops() {
  local user_dir="/mnt/home/$CONFIG_USERNAME/.config/sops/age" system_dir="/mnt${PERSIST_PREFIX}/var/lib/sops/age"
  mkdir -p "$user_dir" "$system_dir"
  chmod 700 "$user_dir" "$system_dir"
  printf '%s\n' "$AGE_KEY" >"$user_dir/keys.txt"
  printf '%s\n' "$AGE_KEY" >"$system_dir/keys.txt"
  chmod 600 "$user_dir/keys.txt" "$system_dir/keys.txt"
  success "SOPS age key saved"
}

setup_totp() {
  local secret_hex secret_b32 oath_file
  secret_hex=$(od -An -tx1 -N20 /dev/urandom | tr -d ' \n')
  secret_b32=$(printf '%s' "$secret_hex" | sed 's/../\\x&/g' | xargs -0 printf '%b' | base32 | tr -d '\n')
  oath_file="/mnt${PERSIST_PREFIX}/etc/users.oath"
  mkdir -p "$(dirname "$oath_file")"
  install -m 600 /dev/null "$oath_file"
  printf 'HOTP/T30/6 %s - %s\n' "$CONFIG_USERNAME" "$secret_hex" >"$oath_file"
  echo ""
  info "Scan this QR code with your authenticator app:"
  echo ""
  nix-shell -p qrencode --run "qrencode -t ANSIUTF8 'otpauth://totp/NixOS:${CONFIG_USERNAME}@${HOST}?secret=${secret_b32}&issuer=NixOS'"
  echo ""
  echo -e "    Backup secret (base32): ${BOLD}$secret_b32${RESET}"
  echo ""
  local verified=false
  for _ in 1 2 3; do
    read -r -p "    Enter OTP code to verify: " otp_code
    local expected
    expected=$(nix-shell -p oath-toolkit --run "oathtool --totp -d 6 $secret_hex")
    if [[ "$otp_code" == "$expected" ]]; then
      verified=true
      break
    fi
    warn "Incorrect. Try again."
  done
  if [[ "$verified" != "true" ]]; then
    warn "Verification failed. Removing secret."
    rm -f "$oath_file"
    return 1
  fi
  success "TOTP configured"
}

setup_tpm() {
  [[ -c /dev/tpmrm0 ]] || {
    warn "No TPM2 device found, skipping."
    return 1
  }
  if ! command -v systemd-cryptenroll &>/dev/null; then
    warn "systemd-cryptenroll not available, skipping TPM enrollment."
    return 1
  fi
  local password_file pcrs="0+7"
  password_file="$(luks_password_file)"
  for dev in "${LUKS_DEVICES[@]}"; do
    info "Enrolling TPM2 on $(basename "$dev")..."
    if systemd-cryptenroll "$dev" --tpm2-device=auto --tpm2-pcrs="$pcrs" --unlock-key-file="$password_file"; then success "$(basename "$dev") enrolled"; else
      warn "$(basename "$dev") failed"
      return 1
    fi
  done
  TPM_ENROLLED=true
  save_state
}

copy_config() {
  local dest="/mnt/home/$CONFIG_USERNAME/repos/nix" home_prefix="/mnt/home/$CONFIG_USERNAME"
  [[ -L "$dest" ]] && rm -f "$dest"
  if [[ ! -d "$dest" ]]; then
    mkdir -p "/mnt/home/$CONFIG_USERNAME/repos"
    if [[ "$INSTALLER_ISO" != true ]]; then
      git -C "$REPO_DIR" add --all
    fi
    cp -aL "$REPO_DIR" "$dest"
    if [[ "$INSTALLER_ISO" == true ]] && command -v git &>/dev/null && timeout 10 git ls-remote "$REPO_URL" HEAD &>/dev/null; then
      local remote_dest="${dest}.remote"
      rm -rf "$remote_dest"
      if git clone --depth 1 --branch main "$REPO_URL" "$remote_dest" &>/dev/null; then
        git -C "$remote_dest" remote set-url origin "$REPO_REMOTE_URL"
        rm -rf "$dest"
        mv "$remote_dest" "$dest"
        success "Online repository cloned to ~${dest#"$home_prefix"}"
        return 0
      fi
      rm -rf "$remote_dest"
      warn "Online repository clone failed; keeping the embedded ISO snapshot."
    fi
    if git -C "$dest" remote get-url origin &>/dev/null; then
      git -C "$dest" remote set-url origin "$REPO_REMOTE_URL"
    fi
    success "Config copied to ~${dest#"$home_prefix"}"
  fi
}

phase_post_install() {
  echo ""
  setup_ssh
  setup_sops
  if [[ "$FEAT_TOTP" == "true" ]]; then
    local oath_file="/mnt${PERSIST_PREFIX}/etc/users.oath"
    if [[ -f "$oath_file" ]]; then
      success "TOTP already configured (cached)"
    elif [[ "$SKIP_TOTP" == "true" || "$YES" == "true" ]]; then
      warn "TOTP setup skipped. Run 'totp-init' after first boot."
    elif ! setup_totp; then
      warn "TOTP setup failed. Run 'totp-init' after first boot."
    fi
  fi
  if [[ "$FEAT_ENCRYPTION" == "true" && ${#LUKS_DEVICES[@]} -gt 0 && "$FEAT_YUBIKEY_LUKS" != "true" ]]; then
    if [[ "$FEAT_SECURE_BOOT" != "true" ]]; then
      setup_tpm || warn "TPM enrollment skipped. Run 'sudo tpm-luks-init' after first boot."
    fi
  fi
  copy_config || warn "Config copy failed. Clone the repo manually after boot."
  echo ""
  info "Fixing home directory ownership..."
  echo ""
  local ownership_command
  printf -v ownership_command 'chown -R %q:users %q' "$CONFIG_USERNAME" "/home/$CONFIG_USERNAME"
  nixos-enter --root /mnt -c "$ownership_command"
  success "Ownership fixed"
}
