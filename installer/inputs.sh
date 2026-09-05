# shellcheck shell=bash
# Interactive and non-interactive input collection.

phase_collect_inputs() {
  [[ -z "$LUKS_PASSWORD" && -n "${NIXOS_LUKS_PASSWORD:-}" ]] && LUKS_PASSWORD="$NIXOS_LUKS_PASSWORD"
  [[ -z "$SSH_KEY" && -n "${NIXOS_SSH_KEY:-}" ]] && SSH_KEY="$NIXOS_SSH_KEY"
  local need_luks=false
  [[ "$DO_FORMAT" == true || "$DO_INSTALL" == true ]] && need_luks=true
  if [[ "$DO_POST_INSTALL" == true && "$FEAT_HAS_LUKS" == "true" &&
    "$FEAT_YUBIKEY_LUKS" != "true" && "$FEAT_SECURE_BOOT" != "true" ]]; then
    need_luks=true
  fi
  if [[ "$FEAT_HAS_LUKS" == "true" && "$need_luks" == true ]]; then
    echo ""
    if [[ -n "$LUKS_PASSWORD" ]]; then
      success "LUKS password ready (cached)"
    elif [[ "$YES" == true ]]; then
      error "Encryption enabled but no LUKS password. Use -p PASSWORD."
    else
      info "LUKS Disk Encryption"
      echo ""
      local pass pass_confirm
      read -r -s -p "Enter LUKS password: " pass
      echo
      read -r -s -p "Confirm password: " pass_confirm
      echo
      [[ "$pass" == "$pass_confirm" ]] || error "Passwords do not match."
      LUKS_PASSWORD="$pass"
      success "Password saved"
    fi
  fi
  if [[ "$DO_POST_INSTALL" == true ]]; then
    echo ""
    info "SSH Key (required for SOPS secrets)"
    echo ""
    if [[ -n "$SSH_KEY_FILE" && -f "$SSH_KEY_FILE" ]]; then
      success "SSH key ready (cached)"
    elif [[ -n "$SSH_KEY" ]]; then
      SSH_KEY_FILE="$SSH_KEY"
      [[ -f "$SSH_KEY_FILE" ]] || error "SSH key file not found: $SSH_KEY_FILE"
      success "SSH key ready"
    elif [[ "$YES" == true ]]; then
      error "SSH key required for post-install. Use -s /path/to/key or set NIXOS_SSH_KEY."
    else
      echo -e "    ${BOLD}[1]${RESET} Enter file path"
      echo -e "    ${BOLD}[2]${RESET} Paste key content"
      echo ""
      local choice
      read -r -p "    Choice [1-2]: " choice
      case "$choice" in
        1)
          read -r -p "    Path to SSH private key: " SSH_KEY_FILE
          [[ -f "$SSH_KEY_FILE" ]] || error "File not found: $SSH_KEY_FILE"
          ;;
        2)
          echo "    Paste your ed25519 private key (end with Ctrl+D):"
          SSH_KEY_FILE="$(mktemp)"
          cat >"$SSH_KEY_FILE"
          chmod 600 "$SSH_KEY_FILE"
          ;;
        *) error "Invalid choice." ;;
      esac
      success "SSH key ready"
    fi
  fi
  if [[ "$CONFIG_PASSWORD_LOCKED" == "true" ]]; then
    echo ""
    if [[ -n "$USER_PASSWORD_HASH" ]]; then
      success "Password hash ready (cached)"
    else
      warn "No password set in host config — account would be locked after install."
      echo ""
      info "User Password"
      echo ""
      local pass pass_confirm
      read -r -s -p "Enter password for $CONFIG_USERNAME: " pass
      echo
      read -r -s -p "Confirm password: " pass_confirm
      echo
      [[ "$pass" == "$pass_confirm" ]] || error "Passwords do not match."
      if command -v mkpasswd &>/dev/null; then
        USER_PASSWORD_HASH="$(printf '%s\n' "$pass" | mkpasswd -m sha-512 -s)"
      else
        USER_PASSWORD_HASH="$(printf '%s\n' "$pass" | nix-shell -p mkpasswd --run 'mkpasswd -m sha-512 -s')"
      fi
      success "Password hash generated"
    fi
  fi
  save_state
}
