# SOPS Secrets Management

Encrypted secrets for NixOS configuration using [SOPS](https://github.com/getsops/sops) with [age](https://github.com/FiloSottile/age) encryption.

## Key Flow

```
SSH Key (id_ed25519)
        ↓
   ssh-to-age
        ↓
Age Key (~/.config/sops/age/keys.txt)
        ↓
SOPS encrypts/decrypts secrets
```

The Age key is derived from your SSH key - same SSH key = same Age key on any machine.

## Files

| File | Purpose | In Git? |
|------|---------|---------|
| `sops.encrypted.yaml` | Encrypted secrets | ✅ Yes |
| `sops.decrypted.yaml` | Plaintext secrets | ❌ No (gitignored) |
| `setup.sh` | Generate Age key from SSH key | ✅ Yes |
| `decrypt.sh` | Decrypt secrets for editing | ✅ Yes |
| `encrypt.sh` | Encrypt secrets after editing | ✅ Yes |

## Scripts

### Initial Setup (new machine)

```bash
./setup.sh
```

Converts your SSH key to an Age key and saves it to `~/.config/sops/age/keys.txt`.

### Edit Secrets

```bash
# 1. Decrypt
./decrypt.sh

# 2. Edit sops.decrypted.yaml

# 3. Re-encrypt
./encrypt.sh

# 4. Commit
git add sops.encrypted.yaml
git commit -m "Update secrets"
```

## Managed Secrets

| Secret | Purpose | Used By |
|--------|---------|---------|
| `user/password` | Local login password for the primary user | `modules/system/users.nix` |
| `wifi/<name>/psk` | WiFi WPA2 pre-shared key | `modules/system/networking/wifi.nix` (NetworkManager) |
| `smb/<name>/password` | SMB/CIFS mount credentials | `modules/system/smb.nix` (systemd mount units) |
| `opencode/opencode-go/api-key` | OpenCode Go API key | `modules/home-manager/programs/opencode.nix` |

### WiFi Networks
- `wifi/home/psk` — Home WPA2 PSK

### SMB Shares
- `smb/personal-drive/password` — Personal NAS share credentials
- `smb/pika/password` — Pika server share credentials

### Mumble
- `mumble/certificate` — Optional PKCS#12 identity certificate, imported into Mumble's `net.certificate` setting when enabled
- The host configuration sets the Mumble username to `Sam` and provisions the favorite server declaratively.
- The certificate is stored as an encrypted Base64 value in `sops.encrypted.yaml`; the private key and the original `.p12` file must never be committed.

### Why Secrets Are Encrypted
- **Credentials**: WiFi keys, SMB passwords, API tokens must never appear in plaintext in the Git history.
- **Reproducibility**: The same SOPS file works across all hosts — only the Age key needs to be provisioned on each machine.
- **Auditability**: Changes to secrets are tracked via Git (encrypted), with the decrypted version gitignored.


## Security Notes

- Public key (`age1...` in `.sops.yaml`) is safe to commit.
- Private key (`~/.config/sops/age/keys.txt`) must never be committed.
- Decrypted file (`sops.decrypted.yaml`) is gitignored; delete it after use.

## Recovery

Lost your Age key? If you have your SSH key:

```bash
./setup.sh  # regenerates the same Age key
```

No SSH key? You'll need to re-encrypt with a new key (requires knowing the plaintext secrets).
