# shellcheck shell=bash
# Disko partitioning and mounting.

disko_reference() {
  local disko_ref
  disko_ref=$(nix flake metadata "path:${REPO_DIR}" --json 2>/dev/null |
    jq -r '.locks.nodes.disko.locked | "github:\(.owner)/\(.repo)/\(.rev)"')
  if [[ -n "$disko_ref" && "$disko_ref" != "null" ]]; then
    printf '%s\n' "$disko_ref"
  else
    printf '%s\n' "github:nix-community/disko"
  fi
}

phase_partition() {
  [[ "$FEAT_HAS_LUKS" == "true" ]] && luks_password_file >/dev/null
  echo ""
  # shellcheck disable=SC2054
  local disko_args=(--mode destroy,format,mount --flake "$REPO_DIR#$HOST" --yes-wipe-all-disks)
  if [[ "$INSTALLER_ISO" == true ]]; then
    command -v disko &>/dev/null || error "Disko is missing from the installer ISO."
    disko "${disko_args[@]}" || error "Disko failed. Check disk IDs in hosts/$HOST/disko.nix"
  else
    local disko_ref
    disko_ref=$(disko_reference)
    nix run "$disko_ref" -- "${disko_args[@]}" || error "Disko failed. Check disk IDs in hosts/$HOST/disko.nix"
  fi
  if [[ "$FEAT_HAS_LUKS" == "true" ]]; then
    command -v cryptsetup &>/dev/null || error "Required command not found: cryptsetup"
    for device in "${LUKS_DEVICES[@]}"; do
      cryptsetup open --test-passphrase --key-file "$(luks_password_file)" "$device" ||
        error "The LUKS password does not unlock $device. Check the password and retry."
    done
    success "LUKS password verified"
  fi
  success "Disks partitioned and mounted at /mnt"
}

phase_mount() {
  local disko_args=(--mode mount --flake "$REPO_DIR#$HOST")
  if [[ "$INSTALLER_ISO" == true ]]; then
    command -v disko &>/dev/null || error "Disko is missing from the installer ISO."
    disko "${disko_args[@]}" || error "Disko mount failed. Are the disks connected?"
  else
    local disko_ref
    disko_ref=$(disko_reference)
    nix run "$disko_ref" -- "${disko_args[@]}" || error "Disko mount failed. Are the disks connected?"
  fi
  success "Existing disks mounted at /mnt"
}
