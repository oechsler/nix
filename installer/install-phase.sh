# shellcheck shell=bash
# shellcheck disable=SC2034
# NixOS installation and configuration versioning.

phase_hardware_config() {
  local host_dir writable_repo
  if [[ "$INSTALLER_ISO" == true ]]; then
    writable_repo="/tmp/nixos-installer-hardware-config"
    rm -rf -- "$writable_repo"
    mkdir -p -- "$writable_repo"
    cp -aL "$REPO_DIR"/. "$writable_repo"/
    REPO_DIR="$writable_repo"
  fi
  host_dir="$REPO_DIR/hosts/$HOST"
  [[ -d "$host_dir" ]] || error "Host directory not found: $host_dir"
  command -v nixos-generate-config &>/dev/null || error "Required command not found: nixos-generate-config"
  info "Generating hardware configuration for $HOST..."
  nixos-generate-config --show-hardware-config \
    2> >(sed '/^ERROR: Not a Btrfs subvolume: Invalid argument$/d' >&2) \
    >"$host_dir/hardware-configuration.generated.nix" ||
    error "Hardware configuration generation failed."
  if git -C "$REPO_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
    git -C "$REPO_DIR" add "$host_dir/hardware-configuration.generated.nix"
  fi
  success "Hardware configuration written to $host_dir/hardware-configuration.generated.nix"
}

phase_state_version() {
  local host_dir="$REPO_DIR/hosts/$HOST"
  if [[ "$INSTALLER_ISO" == true ]]; then
    success "Using prebuilt NixOS version"
    return
  fi
  command -v grep &>/dev/null || error "Required command not found: grep"
  command -v sed &>/dev/null || error "Required command not found: sed"
  command -v nix &>/dev/null || error "Required command not found: nix"
  local version
  version="$(nix eval --raw "$REPO_DIR#nixosConfigurations.${HOST}.pkgs.lib.version" | grep -o '^[0-9]*\.[0-9]*')"
  echo ""
  success "NixOS version: $version"
  sed -i "s|system\.stateVersion = \"[^\"]*\"|system.stateVersion = \"$version\"|" "$host_dir/configuration.nix"
  if [[ -f "$host_dir/home.nix" ]]; then
    sed -i "s|home\.stateVersion = \"[^\"]*\"|home.stateVersion = \"$version\"|" "$host_dir/home.nix"
  fi
  if [[ -n "$USER_PASSWORD_HASH" ]]; then
    local escaped_hash
    escaped_hash="$(printf '%s' "$USER_PASSWORD_HASH" | sed 's/[&\\]/\\&/g')"
    if grep -q 'user\.hashedPassword' "$host_dir/configuration.nix"; then
      sed -i "s|user\.hashedPassword = \"[^\"]*\"|user.hashedPassword = \"$escaped_hash\"|" "$host_dir/configuration.nix"
    else
      sed -i '$i\  user.hashedPassword = "'"$escaped_hash"'";' "$host_dir/configuration.nix"
    fi
    success "Password hash written to configuration.nix"
  fi
  git -C "$REPO_DIR" add "$host_dir/"
}

phase_install() {
  local host_dir="$REPO_DIR/hosts/$HOST" avail_gb max_jobs
  for command_name in awk mkdir; do
    command -v "$command_name" &>/dev/null || error "Required command not found: $command_name"
  done
  if [[ "$INSTALLER_ISO" != true ]]; then
    for command_name in git nixos-generate-config; do
      command -v "$command_name" &>/dev/null || error "Required command not found: $command_name"
    done
  fi
  command -v nixos-install &>/dev/null || error "Required command not found: nixos-install"
  avail_gb=$(awk '/^MemAvailable:/{printf "%d", $2/1024/1024}' /proc/meminfo)
  max_jobs=$((avail_gb / 4))
  ((max_jobs < 1)) && max_jobs=1
  echo ""
  success "RAM available: ${avail_gb} GB — using --max-jobs ${max_jobs}"
  echo ""
  [[ "$FEAT_ENCRYPTION" == "true" ]] && luks_password_file >/dev/null
  if [[ "$INSTALLER_ISO" == true ]]; then
    success "Using prebuilt system closure from installer ISO"
  else
    info "Generating hardware configuration..."
    echo ""
    nixos-generate-config --root /mnt --show-hardware-config \
      2> >(sed '/^ERROR: Not a Btrfs subvolume: Invalid argument$/d' >&2) \
      >"$host_dir/hardware-configuration.generated.nix"
    nix flake lock "$REPO_DIR"
    git -C "$REPO_DIR" add "$host_dir/hardware-configuration.generated.nix" "$REPO_DIR/flake.lock"
    success "Hardware configuration generated"
    echo ""
  fi
  mkdir -p /mnt/tmp
  export TMPDIR=/mnt/tmp
  if [[ "$INSTALLER_ISO" == true ]]; then
    local system_path
    system_path=$(jq -r --arg host "$HOST" '.hosts[$host].system // empty' "$ISO_MANIFEST")
    [[ -n "$system_path" && -e "$system_path" ]] || error "Prebuilt system closure for $HOST is missing from the installer ISO."
    nixos-install --system "$system_path" --no-root-password --max-jobs "$max_jobs" || error "nixos-install failed. Check the output above."
  elif [[ "$FEAT_SECURE_BOOT" == "true" ]]; then
    local override_nix="$host_dir/secure-boot-install-override.nix"
    SECURE_BOOT_OVERRIDE_FILE="$override_nix"
    SECURE_BOOT_CONFIG_FILE="$host_dir/configuration.nix"
    printf '{ lib, ... }: { features.secureBoot.enable = lib.mkForce false; }\n' >"$override_nix"
    sed -i "/imports = \[/a\\    ./secure-boot-install-override.nix" "$host_dir/configuration.nix"
    git -C "$REPO_DIR" add "$override_nix" "$host_dir/configuration.nix"
    local install_ok=true
    nixos-install --flake "$REPO_DIR#$HOST" --no-root-password --max-jobs "$max_jobs" || install_ok=false
    sed -i '/secure-boot-install-override\.nix/d' "$host_dir/configuration.nix"
    rm -f "$override_nix"
    git -C "$REPO_DIR" add "$host_dir/configuration.nix"
    git -C "$REPO_DIR" rm --cached "$override_nix" 2>/dev/null || true
    [[ "$install_ok" == true ]] || error "nixos-install failed. Check the output above."
  else
    nixos-install --flake "$REPO_DIR#$HOST" --no-root-password --max-jobs "$max_jobs" || error "nixos-install failed. Check the output above."
  fi
  success "NixOS installed"
}
