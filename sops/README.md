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

The Age identity is derived from the SSH private key. The same private key
produces the same identity on another machine, but the key must be available
there and the repository recipients must still permit decryption.

## Files

| File                  | Purpose                       | In Git?            |
| --------------------- | ----------------------------- | ------------------ |
| `sops.encrypted.yaml` | Encrypted secrets             | ✅ Yes             |
| `sops.decrypted.yaml` | Plaintext secrets             | ❌ No (gitignored) |
| `setup.sh`            | Generate Age key from SSH key | ✅ Yes             |
| `decrypt.sh`          | Decrypt secrets for editing   | ✅ Yes             |
| `encrypt.sh`          | Encrypt secrets after editing | ✅ Yes             |

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

| Secret                         | Purpose                              | Used By                                      |
| ------------------------------ | ------------------------------------ | -------------------------------------------- |
| `mumble/certificate`           | Optional Mumble identity certificate | `modules/home-manager/programs/mumble.nix`   |
| `opencode/mcp/homeassistant/token` | Home Assistant MCP token        | `modules/home-manager/programs/opencode.nix` |
| `opencode/provider/opencode-go/api-key` | OpenCode Go API key         | `modules/home-manager/programs/opencode.nix` |
| `smb/<name>/password`          | SMB/CIFS share password              | `modules/system/smb.nix`                     |
| `user/password`                | Local login password                 | `modules/system/users.nix`                   |
| `wifi/<name>/psk`              | WiFi pre-shared key                  | `modules/system/networking/wifi.nix`         |

Secret names containing `<name>` use the identifier of the corresponding
declarative network or share configuration.

The Mumble certificate is optional. When `mumble/certificate` exists in SOPS,
the module imports it into the local Mumble profile. Without the secret, Mumble
continues to work without a client certificate.

### Mumble

- `mumble/certificate` — Optional PKCS#12 identity certificate, imported into Mumble's `certificate` setting when present
- The certificate is stored as an encrypted Base64 value in `sops.encrypted.yaml`; the private key and the original `.p12` file must never be committed.

### Why Secrets Are Encrypted

- **Credentials**: WiFi keys, SMB passwords, API tokens, and certificates must never appear in plaintext in the Git history.
- **Reproducibility**: The same encrypted SOPS file can be used by every host with an appropriate Age key.
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
