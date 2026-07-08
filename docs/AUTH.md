# Authentication

Two-factor authentication via TOTP and/or YubiKey. Configured in `modules/system/auth.nix`.

## Overview

| Method | Default | Setup |
|--------|---------|-------|
| TOTP (Time-based One-Time Password) | enabled | `sudo totp-init` |
| YubiKey PAM (sudo, SSH) | on when `unlockMethod = "yubikey"` | `sudo yubikey-init` |
| YubiKey FIDO2 LUKS unlock (boot) | via `features.encryption.unlockMethod` | `sudo yubikey-luks-init` |
| TPM2 LUKS unlock (boot) | via `features.encryption.unlockMethod` | `sudo tpm-luks-init` |

Both PAM methods work independently or combined. Password serves as a local fallback only — it is never accepted over SSH.

> **Note:** SDDM, polkit, and hyprlock always use **password only**, regardless of which 2FA method is enabled. This is required so that `pam_gnome_keyring` can capture the login password at SDDM and auto-unlock the GNOME Keyring. YubiKey login skips `pam_gnome_keyring`'s auth phase, leaving the keyring locked.

## Auth Flow

### Login / SDDM

Password only. TOTP is excluded because SDDM's greeter mishandles multi-prompt PAM. YubiKey is excluded so that `pam_gnome_keyring` can capture the password and auto-unlock the GNOME Keyring. SDDM inherits login's PAM configuration.

| Enabled | Auth chain |
|---------|-----------|
| TOTP only | Password |
| YubiKey only | Password |
| Both | Password |

### sudo

Each method is tried in order. The first success grants access, on failure the next method is tried. TOTP allows 3 attempts before falling back.

| Enabled | Auth chain |
|---------|-----------|
| TOTP only | OTP (3 attempts) → Password |
| YubiKey only | YubiKey → Password |
| Both | YubiKey → OTP (3 attempts) → Password |

### Polkit

Password only. TOTP and YubiKey are both excluded — password is required here for the same reason as SDDM: if polkit used a different credential, apps would prompt for the GNOME Keyring password separately on every privileged action.

| Enabled | Auth chain |
|---------|-----------|
| TOTP only | Password |
| YubiKey only | Password |
| Both | Password |

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

TOTP is **enabled by default** (`features.auth.totp.enable = true`). It serves as the primary
2FA method on sudo when no YubiKey is active, and as fallback when YubiKey **is** active.

```text
sudo with TOTP only:   OTP (3 attempts) → Password
sudo with both:        YubiKey → OTP (3 attempts) → Password
```

**Setup**: run `sudo totp-init`, scan the QR code with your authenticator app,
then `sudo nixos-rebuild switch`.

**Adding a second device**: run `sudo totp-init` again and choose "Re-enroll".
Scan the QR code on both devices. The old secret is replaced — previous device
codes stop working after the rebuild.

**Manual verification** (e.g. to check clock drift):
```bash
oathtool --totp -d 6 "$(sudo cat /persist/etc/users.oath | awk '{print $NF}')"
```

**Disable** (not recommended):
```nix
features.auth.totp.enable = false;
```

### YubiKey (PAM)

YubiKey PAM is enabled automatically when `encryption.unlockMethod = "yubikey"`. To enable PAM independently:

```nix
features.auth.yubikey.enable = true;
```

Then register your key:

```bash
sudo yubikey-init
```

This writes credentials to `/etc/u2f_mappings` (or `/persist/etc/u2f_mappings` with impermanence). Rebuild to activate.

To register a backup key, run `sudo yubikey-init` again and choose **Add another key**.

### YubiKey FIDO2 LUKS Unlock

Set the unlock method in your host's `configuration.nix`:

```nix
features.encryption.unlockMethod = "yubikey";
```

This automatically enables YubiKey PAM (`auth.yubikey.enable`) and installs everything needed. For YubiKey PAM without YubiKey LUKS:

```nix
features.encryption.unlockMethod = "tpm2";
features.auth.yubikey.enable = true;
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

Password is the fallback for local services. Stored as plain text in sops (`user/password`), hashed to yescrypt at boot by `user-passwd.service`. No per-host configuration needed.

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
