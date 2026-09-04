# shellcheck shell=bash
# shellcheck disable=SC2034
# Host feature evaluation and keyboard setup.

FEAT_ENCRYPTION=false
FEAT_UNLOCK_METHOD=""
FEAT_IMPERMANENCE=false
PERSIST_PREFIX=""
FEAT_TOTP=false
FEAT_YUBIKEY=false
FEAT_YUBIKEY_LUKS=false
FEAT_SECURE_BOOT=false
FEAT_DESKTOP=false
FEAT_WM=""
FEAT_FORM_FACTOR=""
FEAT_KERNEL=""
FEAT_KERNEL_VERSION=""
FEAT_KEYBOARD=""
FEAT_LANGUAGE=""
CONFIG_USERNAME=""
CONFIG_PASSWORD_LOCKED=false
LUKS_DEVICES=()
TPM_ENROLLED=false

phase_detect_features() {
	if [[ -n "$CONFIG_USERNAME" ]]; then
		echo ""
		success "Features loaded from cache (host: $HOST)"
		echo ""
		return
	fi
	ensure_jq
	echo ""
	info "Reading configuration for $HOST..."
	echo ""
	local json
	if [[ "$INSTALLER_ISO" == true ]]; then
		json=$(jq -c --arg host "$HOST" '.hosts[$host] // empty' "$ISO_MANIFEST")
		[[ -n "$json" ]] || error "Host '$HOST' is missing from the installer ISO manifest."
	else
		json=$(nix eval --json "$REPO_DIR#nixosConfigurations.${HOST}.config" --apply '
    cfg: {
      encryption = cfg.features.encryption.enable;
      unlockMethod = cfg.features.encryption.unlockMethod;
      impermanence = cfg.features.impermanence.enable;
      persistPrefix = cfg.features.impermanence.persistPrefix;
      totp = cfg.features.auth.totp.enable;
      yubikey = cfg.features.auth.yubikey.enable;
      yubikeyLuks = cfg.features.encryption.unlockMethod == "yubikey";
      secureBoot = cfg.features.secureBoot.enable;
      desktop = cfg.features.desktop.enable;
      wm = cfg.features.desktop.wm;
      formFactor = cfg.features.hardware.formFactor;
      kernel = cfg.features.kernel;
      kernelVersion = cfg.boot.kernelPackages.kernel.name;
      keyboard = cfg.locale.keyboard;
      language = cfg.locale.language;
      userName = cfg.user.name;
      passwordLocked = cfg.user.hashedPassword == "!"
        && !(cfg.sops.secrets ? "user/password");
      luksDevices = builtins.attrValues (builtins.mapAttrs (name: dev: dev.device) cfg.boot.initrd.luks.devices);
    }
  }') || error "Failed to evaluate configuration. Check flake syntax."
	fi
	FEAT_ENCRYPTION=$(jq -r '.encryption' <<<"$json")
	FEAT_UNLOCK_METHOD=$(jq -r '.unlockMethod' <<<"$json")
	FEAT_IMPERMANENCE=$(jq -r '.impermanence' <<<"$json")
	PERSIST_PREFIX=$(jq -r '.persistPrefix' <<<"$json")
	FEAT_TOTP=$(jq -r '.totp' <<<"$json")
	FEAT_YUBIKEY=$(jq -r '.yubikey' <<<"$json")
	FEAT_YUBIKEY_LUKS=$(jq -r '.yubikeyLuks' <<<"$json")
	FEAT_SECURE_BOOT=$(jq -r '.secureBoot' <<<"$json")
	FEAT_DESKTOP=$(jq -r '.desktop' <<<"$json")
	FEAT_WM=$(jq -r '.wm' <<<"$json")
	FEAT_FORM_FACTOR=$(jq -r '.formFactor' <<<"$json")
	FEAT_KERNEL=$(jq -r '.kernel' <<<"$json")
	FEAT_KERNEL_VERSION=$(jq -r '.kernelVersion' <<<"$json")
	FEAT_KEYBOARD=$(jq -r '.keyboard' <<<"$json")
	FEAT_LANGUAGE=$(jq -r '.language' <<<"$json")
	CONFIG_USERNAME=$(jq -r '.userName' <<<"$json")
	CONFIG_PASSWORD_LOCKED=$(jq -r '.passwordLocked' <<<"$json")
	mapfile -t LUKS_DEVICES < <(jq -r '.luksDevices[]' <<<"$json")
	echo -e "    Host:          ${BOLD}$HOST${RESET}"
	echo -e "    Username:      ${BOLD}$CONFIG_USERNAME${RESET}"
	[[ -n "$FEAT_FORM_FACTOR" && "$FEAT_FORM_FACTOR" != "null" ]] && echo -e "    Form factor:   ${BOLD}$FEAT_FORM_FACTOR${RESET}"
	[[ -n "$FEAT_KERNEL" && "$FEAT_KERNEL" != "null" ]] && echo -e "    Kernel:        ${BOLD}$FEAT_KERNEL${RESET} (${FEAT_KERNEL_VERSION})"
	[[ "$FEAT_DESKTOP" == "true" ]] && echo -e "    Desktop:       ${BOLD}$FEAT_WM${RESET}"
	[[ -n "$FEAT_KEYBOARD" && "$FEAT_KEYBOARD" != "null" ]] && echo -e "    Keyboard:      ${BOLD}$FEAT_KEYBOARD${RESET}"
	[[ -n "$FEAT_LANGUAGE" && "$FEAT_LANGUAGE" != "null" ]] && echo -e "    Language:      ${BOLD}$FEAT_LANGUAGE${RESET}"
	echo -e "    Encryption:    $(label_bool "$FEAT_ENCRYPTION")"
	echo -e "    Impermanence:  $(label_bool "$FEAT_IMPERMANENCE")"
	echo -e "    TOTP 2FA:      $(label_bool "$FEAT_TOTP")"
	echo -e "    YubiKey:       $(label_bool "$FEAT_YUBIKEY")"
	echo -e "    Secure Boot:   $(label_bool "$FEAT_SECURE_BOOT")"
	if [[ "$FEAT_ENCRYPTION" == "true" && ${#LUKS_DEVICES[@]} -gt 0 ]]; then
		echo -e "    LUKS devices:  ${DIM}${#LUKS_DEVICES[@]} partition(s)${RESET}"
		case "$FEAT_UNLOCK_METHOD" in
		tpm2) unlock_label="TPM2" ;;
		yubikey) unlock_label="YubiKey FIDO2" ;;
		*) unlock_label="Password" ;;
		esac
		echo -e "    LUKS Unlock:   ${GREEN}${unlock_label}${RESET}"
	fi
	if [[ "$CONFIG_PASSWORD_LOCKED" == "true" && -z "$USER_PASSWORD_HASH" ]]; then
		echo -e "    Password:      ${YELLOW}not set${RESET}"
	elif [[ "$CONFIG_PASSWORD_LOCKED" == "false" ]]; then
		echo -e "    Password:      ${GREEN}via sops${RESET}  ${DIM}(set at boot by user-passwd.service)${RESET}"
	else
		echo -e "    Password:      ${GREEN}set in config${RESET}"
	fi
	echo ""
	success "Features detected"
	save_state
}

apply_keyboard_layout() {
	[[ "$DRY_RUN" == true ]] && return 0
	[[ -n "$FEAT_KEYBOARD" && "$FEAT_KEYBOARD" != "null" ]] || return 0
	if command -v loadkeys &>/dev/null; then
		loadkeys "$FEAT_KEYBOARD" 2>/dev/null || warn "Could not apply console keyboard layout: $FEAT_KEYBOARD"
	fi
	if command -v setxkbmap &>/dev/null && [[ -n "${DISPLAY:-}" ]]; then
		setxkbmap "$FEAT_KEYBOARD" 2>/dev/null || warn "Could not apply X11 keyboard layout: $FEAT_KEYBOARD"
	fi
	if command -v localectl &>/dev/null; then
		localectl set-keymap "$FEAT_KEYBOARD" 2>/dev/null || true
		localectl set-x11-keymap "$FEAT_KEYBOARD" 2>/dev/null || true
	fi
	success "Keyboard layout: $FEAT_KEYBOARD"
}
