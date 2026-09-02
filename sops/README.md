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

## Secret Structure

The SOPS document is a shared encrypted data source, not a fixed inventory of
secrets. It contains common foundations as well as credentials required by
individual hosts. Modules define which paths they consume, while host
configuration decides which features and therefore which paths are relevant.

The hierarchy is intentionally flexible. Group secrets by feature, service,
provider, host, or another stable identifier that makes their use clear:

```yaml
service:
  instance:
    credential: value
```

Names and nesting should match the corresponding module configuration whenever
possible. Dynamic entries use the identifier from the host configuration, for
example a network, share, provider, or MCP name. Add a short comment before
each section and individual entry describing its purpose and consumer.

OpenCode follows this pattern for example:

```yaml
opencode:
  provider:
    provider-name:
      api-key: "encrypted-value"
  mcp:
    mcp-name:
      token: "encrypted-value"
```

The Nix module references these values by path. A credential can be optional
or required depending on the feature using it. For example, a client
certificate may be imported when present, while a provider API key is checked
when that provider is enabled.

Do not treat the current paths in the encrypted file as a complete contract.
When adding or removing a feature, update the encrypted document and the
module that consumes the path together.

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
