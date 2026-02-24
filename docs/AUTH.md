# Authentication

Two-factor authentication via TOTP and/or YubiKey. Configured in `modules/system/auth.nix`.

## Overview

| Method | Default | Setup |
|--------|---------|-------|
| TOTP (Time-based One-Time Password) | enabled | `sudo totp-init` |
| YubiKey (FIDO2, touch only) | disabled | `sudo yubikey-init` |

Both methods work independently or combined. Password serves as a local fallback only — it is never accepted over SSH.

## Auth Flow

### Local (login, SDDM, sudo, polkit)

Each method is tried in order. The first success grants access, on failure the next method is tried.

| Enabled | Auth chain |
|---------|-----------|
| TOTP only | OTP → Password |
| YubiKey only | YubiKey → Password |
| Both | YubiKey → OTP → Password |

### SSH

SSH uses two-stage authentication: first the SSH key, then a second factor via PAM.

1. **Public-Key**: OpenSSH verifies `~/.ssh/authorized_keys` (synced from GitHub via `ssh.nix`)
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

### YubiKey

Enable in your host's `configuration.nix`:

```nix
features.auth.yubikey.enable = true;
```

Then register your key:

```bash
sudo yubikey-init
```

This writes credentials to `/etc/u2f_mappings`. Rebuild to activate.

To register a backup key, run `sudo yubikey-init` again and choose **Add another key**.

### Password

Password is the fallback for local services. Default is locked (`"!"`). Each host sets its own hash:

```nix
# Generate: mkpasswd -m sha-512
user.hashedPassword = "$6$...";
```

## Files

| File | Purpose | Persisted |
|------|---------|-----------|
| `/etc/users.oath` | TOTP secrets | Yes (impermanence) |
| `/etc/u2f_mappings` | YubiKey credentials | Yes (impermanence) |
| `modules/system/auth.nix` | PAM configuration, CLI tools | — |
| `modules/system/users.nix` | Password hash (default: locked) | — |

## Disabling

To disable TOTP (not recommended):

```nix
features.auth.totp.enable = false;
```

Without any 2FA enabled, authentication falls back to password only.
