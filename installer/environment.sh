# shellcheck shell=bash
# Environment validation and host selection.

luks_password_file() {
  if [[ -z "$LUKS_PASSWORD_FILE" ]]; then
    LUKS_PASSWORD_FILE="$STATE_DIR/luks-password"
    : >"$LUKS_PASSWORD_FILE"
    chmod 600 "$LUKS_PASSWORD_FILE"
    printf '%s' "$LUKS_PASSWORD" >"$LUKS_PASSWORD_FILE"
  fi
  echo "$LUKS_PASSWORD_FILE"
}

phase_validate() {
  [[ "${_HEADER_PRINTED:-}" != "1" ]] && {
    info "NixOS Installer"
    echo ""
    export _HEADER_PRINTED=1
  }
  [[ -e /etc/NIXOS ]] || error "Not a NixOS system. Boot from a NixOS ISO first."
  if [[ $EUID -ne 0 ]]; then
    exec sudo env _HEADER_PRINTED=1 "$0" "${ORIGINAL_ARGS[@]}"
  fi
  if [[ "$DRY_RUN" != true ]]; then
    mkdir -p -- "$STATE_DIR"
    chmod 700 "$STATE_DIR"
    chown root:root "$STATE_DIR"
  fi
  if [[ "$DRY_RUN" == true ]]; then
    warn "Dry-run mode: no changes will be made"
    echo ""
  fi
  local root_fstype
  root_fstype="$(findmnt -n -o FSTYPE /)"
  IS_LIVE=false
  [[ "$root_fstype" == "tmpfs" ]] && IS_LIVE=true
  command -v nix &>/dev/null || error "Nix is not available."
  export NIX_CONFIG="experimental-features = nix-command flakes
warn-dirty = false"
  success "Environment OK"
}

ensure_jq() {
  if ! command -v jq &>/dev/null; then
    [[ "$DRY_RUN" != true ]] || error "jq is required for --dry-run but is not installed."
    nix profile install nixpkgs#jq 2>/dev/null || nix-env -iA nixos.jq 2>/dev/null
  fi
  command -v jq &>/dev/null || error "jq is required but could not be installed."
}

phase_select_host() {
  local hosts=() descriptions=()
  if [[ "$INSTALLER_ISO" == true ]]; then
    ensure_jq
    mapfile -t hosts < <(jq -r '.hosts | keys[]' "$ISO_MANIFEST")
    for name in "${hosts[@]}"; do
      local desc=""
      if [[ -f "$REPO_DIR/hosts/$name/configuration.nix" ]]; then
        desc="$(head -1 "$REPO_DIR/hosts/$name/configuration.nix" | sed 's/^# *//' | sed 's/ *$//')"
      fi
      descriptions+=("$desc")
    done
  else
    for dir in "$REPO_DIR"/hosts/*/; do
      local name
      name="$(basename "$dir")"
      [[ -f "$dir/configuration.nix" ]] || continue
      hosts+=("$name")
      local desc
      desc="$(head -1 "$dir/configuration.nix" | sed 's/^# *//' | sed 's/ *$//')"
      descriptions+=("$desc")
    done
  fi
  [[ ${#hosts[@]} -gt 0 ]] || error "No hosts found in $REPO_DIR/hosts/"
  if [[ -z "$HOST" && "$IS_LIVE" != true ]]; then
    local current_hostname
    current_hostname="$(hostname)"
    for h in "${hosts[@]}"; do
      if [[ "$h" == "$current_hostname" ]]; then
        HOST="$current_hostname"
        success "Host detected from hostname: $HOST"
        return
      fi
    done
  fi
  if [[ -n "$HOST" ]]; then
    local found=false
    for h in "${hosts[@]}"; do [[ "$h" == "$HOST" ]] && found=true; done
    [[ "$found" == true ]] || error "Host '$HOST' not found. Available: ${hosts[*]}"
    return
  fi
  echo ""
  info "Available hosts:"
  echo ""
  for i in "${!hosts[@]}"; do
    echo -e "    ${BOLD}[$((i + 1))]${RESET} ${hosts[$i]}  ${DIM}— ${descriptions[$i]}${RESET}"
  done
  echo ""
  local choice
  read -r -p "    Select host [1-${#hosts[@]}]: " choice
  if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#hosts[@]})); then
    HOST="${hosts[$((choice - 1))]}"
  else
    error "Invalid selection."
  fi
}
