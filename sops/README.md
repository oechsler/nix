# SOPS Secrets Management

Encrypted secrets for NixOS configuration using [SOPS](https://github.com/getsops/sops) with [age](https://github.com/FiloSottile/age) encryption.

## How it Works

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

| Secret | Used By |
|--------|---------|
| `wifi.home.ssid/psk` | NetworkManager WiFi profiles |
| `smb.personal-drive.*` | SMB mount credentials |
| `kubernetes.kubeconfig` | kubectl configuration |

## Security Notes

- **Public key** (`age1...` in `.sops.yaml`) - safe to commit
- **Private key** (`~/.config/sops/age/keys.txt`) - never commit!
- **Decrypted file** (`sops.decrypted.yaml`) - gitignored, delete after use

## Recovery

Lost your Age key? If you have your SSH key:

```bash
./setup.sh  # regenerates the same Age key
```

No SSH key? You'll need to re-encrypt with a new key (requires knowing the plaintext secrets).
