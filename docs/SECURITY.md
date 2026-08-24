# Security Overview

This document summarizes the security boundaries and trade-offs in the
configuration. It is a guide to the defaults, not a guarantee against every
class of compromise.

## Layers

### Disk Encryption

LUKS2 encrypts the root and data storage; the EFI system partition remains
unencrypted. The unlock method is configured per host:

| Method   | Feature flag                                          | Behavior                       |
| -------- | ----------------------------------------------------- | ------------------------------ |
| TPM2     | `features.encryption.unlockMethod = "tpm2"` (default) | Auto-unlock, sealed to PCR 0+7 |
| YubiKey  | `features.encryption.unlockMethod = "yubikey"`        | FIDO2 touch at boot            |
| Password | `features.encryption.unlockMethod = "password"`       | LUKS passphrase prompt         |

To disable encryption entirely:

```nix
features = {
  encryption.enable = false;
};
```

Setup: TPM enrollment via `sudo tpm-luks-init`, YubiKey via `sudo yubikey-luks-init`.

### Secure Boot

UEFI Secure Boot via lanzaboote. Prevents unsigned code from running at boot. Disabled by default (requires manual key enrollment).

```nix
features = {
  secureBoot.enable = true;
};
```

Setup: see [INSTALL.md — Secure Boot](INSTALL.md#secure-boot-setup).

### Impermanence

Root filesystem (`/`) is wiped on every boot via Btrfs rollback when
impermanence is enabled. Only explicitly declared paths in `/persist` survive
reboots. This reduces persistence of changes stored on the ephemeral root
filesystem; it does not protect persistent paths, user data, firmware, or a
running system.

```nix
features = {
  impermanence.enable = true;
};
```

**Trade-off**: `/persist` is the single point of trust — anything written there survives, including potential malware. Keep the persist list minimal.

### Authentication

Multi-factor authentication is available for sudo and SSH. Graphical login,
hyprlock, and other local desktop prompts use a password credential; LDAP can
provide that credential when enabled.

| Method          | Where                      | Setup                                          |
| --------------- | -------------------------- | ---------------------------------------------- |
| TOTP            | sudo, SSH                  | `sudo totp-init`                               |
| YubiKey (FIDO2) | sudo, SSH                  | `sudo yubikey-init`                            |
| Password        | local or LDAP-backed login | SOPS-provided local password is hashed at boot |

SSH enforces public-key + second factor (`publickey,keyboard-interactive`). Password-only SSH is disabled.

Details: [AUTH.md](AUTH.md)

### Firewall

NixOS firewall (`networking.firewall`) is enabled by default. All inbound ports are closed unless explicitly opened per service via `openFirewall = true` or `allowedTCPPorts`.

No additional firewall tool (ufw, firewalld) is needed — the NixOS firewall is declarative and managed through the Nix configuration.

### SSH Hardening

SSH server is off by default (`features.ssh.enable = false`). When enabled:

- Password authentication disabled
- Public keys auto-synced from GitHub (every 15 min)
- 2FA required as second authentication stage

### Secrets Management

Secrets such as WiFi passwords, SMB credentials, API keys, and Mumble
certificates are encrypted with SOPS and age. The repository uses an
SSH-derived Age identity. Secrets are never stored in plain text in the
repository, but are necessarily materialized on the installed system at
runtime; see [sops/README.md](../sops/README.md).

## Summary

| Layer          | Primary protection                                      |
| -------------- | ------------------------------------------------------- |
| LUKS           | Physical disk access, theft                             |
| Secure Boot    | Bootkit, unsigned kernel/initrd                         |
| Impermanence   | Persistence of changes on the ephemeral root filesystem |
| TOTP / YubiKey | Stolen passwords, unauthorized login                    |
| Firewall       | Network-based attacks, open ports                       |
| SSH hardening  | Brute force, password-based SSH                         |
| SOPS           | Secrets leaking from the repository                     |
