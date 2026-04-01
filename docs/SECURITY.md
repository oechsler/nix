# Security Overview

Summary of the security layers in this NixOS configuration.

## Layers

### Disk Encryption

LUKS2 full disk encryption on all partitions. Optional TPM2 auto-unlock (PCR 0+7) seals to firmware and Secure Boot state — falls back to password if either changes.

```nix
features.encryption.enable = true;  # default
```

Setup: automatic during install. TPM enrollment via `sudo tpm-init` after first boot.

### Secure Boot

UEFI Secure Boot via lanzaboote. Prevents unsigned code from running at boot. Disabled by default (requires manual key enrollment).

```nix
features.secureBoot.enable = true;
```

Setup: see [INSTALL.md — Secure Boot](INSTALL.md#secure-boot-setup).

### Impermanence

Root filesystem (`/`) is wiped on every boot via btrfs rollback. Only explicitly declared paths in `/persist` survive reboots. This eliminates persistent malware, configuration drift, and accumulated state.

```nix
features.impermanence.enable = true;  # default
```

**Trade-off**: `/persist` is the single point of trust — anything written there survives, including potential malware. Keep the persist list minimal.

### Authentication

Multi-factor authentication on sudo, SSH, and local login surfaces.

| Method | Where | Setup |
|--------|-------|-------|
| TOTP | sudo, SSH | `sudo totp-init` |
| YubiKey (FIDO2) | sudo, SSH | `sudo yubikey-init` |
| Password | local fallback only | plain text in sops (`user/password`), hashed at boot |

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

All secrets (WiFi passwords, SMB credentials) are encrypted with SOPS + age. The age key is derived from the SSH ed25519 key. Secrets are never stored in plain text in the repository.

## Summary

| Layer | Protects against |
|-------|-----------------|
| LUKS | Physical disk access, theft |
| Secure Boot | Bootkit, unsigned kernel/initrd |
| Impermanence | Persistent malware, config drift |
| TOTP / YubiKey | Stolen passwords, unauthorized login |
| Firewall | Network-based attacks, open ports |
| SSH hardening | Brute force, password-based SSH |
| SOPS | Secrets leaking from the repository |
