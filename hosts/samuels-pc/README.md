# samuels-pc

Desktop PC. See [hosts README](../) for general installation steps.

| Setting | Value |
|---------|-------|
| Device | `/dev/nvme0n1` |
| Swap | 34GB |
| RAM | 32GB |
| Scale | 1.0x |

```bash
# Disko
sudo nix --experimental-features "nix-command flakes" run github:nix-community/disko -- \
  --mode disko /tmp/nix/hosts/samuels-pc/disko.nix

# Install
sudo nixos-install --flake /tmp/nix#samuels-pc --no-root-passwd

# Rebuild
sudo nixos-rebuild switch --flake .#samuels-pc
```
