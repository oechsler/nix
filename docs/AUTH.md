# Authentication

Two-factor authentication via TOTP and/or YubiKey. Configured in `modules/system/auth.nix`.

## Overview

| Method | Default | Setup |
|--------|---------|-------|
| TOTP (Time-based One-Time Password) | enabled | `sudo totp-init` |
| YubiKey PAM (login, sudo, SSH, polkit) | disabled | `sudo yubikey-init` |
| YubiKey FIDO2 LUKS unlock (boot) | on when `yubikey.enable = true` | `sudo yubikey-luks-init` |

Both PAM methods work independently or combined. Password serves as a local fallback only — it is never accepted over SSH.

## Auth Flow

### Login / SDDM

Password only (TOTP excluded — SDDM's greeter mishandles multi-prompt PAM). YubiKey works because it only needs touch. SDDM inherits login's PAM configuration.

| Enabled | Auth chain |
|---------|-----------|
| TOTP only | Password |
| YubiKey only | YubiKey → Password |
| Both | YubiKey → Password |

### sudo

Each method is tried in order. The first success grants access, on failure the next method is tried. TOTP allows 3 attempts before falling back.

| Enabled | Auth chain |
|---------|-----------|
| TOTP only | OTP (3 attempts) → Password |
| YubiKey only | YubiKey → Password |
| Both | YubiKey → OTP (3 attempts) → Password |

### Polkit

Polkit uses a different auth flow because `polkit-agent-helper-1` sends each PAM prompt individually — TOTP's multi-round conversation is unreliable with this protocol. YubiKey works because it only needs touch (no text input).

| Enabled | Auth chain |
|---------|-----------|
| TOTP only | Password only (TOTP excluded) |
| YubiKey only | YubiKey touch or Password |
| Both | YubiKey touch or Password |

### SSH

SSH uses two-stage authentication: first the SSH key, then a second factor via PAM.

1. **Public-Key**: OpenSSH verifies `~/.ssh/authorized_keys` (synced from GitHub via `ssh.nix`, every 15 min)
2. **Keyboard-Interactive**: OpenSSH hands off to PAM, which prompts for TOTP/YubiKey

This is enforced by `AuthenticationMethods = "publickey,keyboard-interactive"` — both stages must succeed. Password auth (`PasswordAuthentication`) and unix PAM auth (`unixAuth`) are disabled, so there is no password fallback over SSH.

| Enabled | Auth chain |
|---------|-----------|
| TOTP only | Public-Key + OTP |
| YubiKey only | Public-Key + YubiKey |
| Both | Public-Key + (YubiKey or OTP) |

Requires `features.ssh.enable = true` on the host for the SSH server to run.

## Setup

### TOTP

TOTP is set up automatically during installation (`install.sh`). To reconfigure on an existing system:

```bash
sudo totp-init
```

This generates a new secret, writes it to `/etc/users.oath`, and displays a QR code to scan with an authenticator app (Google Authenticator, Aegis, etc.).

After setup, activate with:

```bash
sudo nixos-rebuild switch
```

### YubiKey (PAM)

Enable in your host's `configuration.nix`:

```nix
features.auth.yubikey.enable = true;

# Optional: require FIDO2 PIN in addition to touch
features.auth.yubikey.pin = true;
```

Then register your key:

```bash
sudo yubikey-init
```

This writes credentials to `/etc/u2f_mappings` (or `/persist/etc/u2f_mappings` with impermanence). Rebuild to activate.

To register a backup key, run `sudo yubikey-init` again and choose **Add another key**.

### YubiKey FIDO2 LUKS Unlock

When `features.auth.yubikey.enable = true`, LUKS unlock at boot automatically switches from TPM2 to YubiKey FIDO2 (`yubikey.luks.enable` defaults to `yubikey.enable`). To keep TPM2 while using YubiKey for PAM:

```nix
features.auth.yubikey.enable = true;
features.auth.yubikey.luks.enable = false;  # keep TPM2
```

**Before switching from TPM to YubiKey** — wipe the TPM slot first:

```bash
sudo tpm-luks-init   # choose "wipe"
```

Then rebuild and enroll the YubiKey:

```bash
sudo nixos-rebuild switch --flake .#hostname
sudo yubikey-luks-init   # choose "enroll"
```

At every subsequent boot: plug in the YubiKey and touch it when prompted.

To re-enroll or wipe the FIDO2 slot on an existing system:

```bash
sudo yubikey-luks-init
```

### Password

Password is the fallback for local services. Default is locked (`"!"`). Each host sets its own hash:

```nix
# Generate: mkpasswd -m sha-512
user.hashedPassword = "$6$...";
```

## Files

Auth files use `persistPrefix` directly (not impermanence bind-mounts) because `pam_oath`/`pam_u2f` update files via `temp + rename()`, which fails across bind-mount boundaries.

| File | Purpose |
|------|---------|
| `/persist/etc/users.oath` (or `/etc/users.oath` without impermanence) | TOTP secrets |
| `/persist/etc/u2f_mappings` (or `/etc/u2f_mappings` without impermanence) | YubiKey credentials |
| `modules/system/auth.nix` | PAM configuration, CLI tools |
| `modules/system/users.nix` | Password hash (default: locked) |

## Disabling

To disable TOTP (not recommended):

```nix
features.auth.totp.enable = false;
```

Without any 2FA enabled, authentication falls back to password only.
