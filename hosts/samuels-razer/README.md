# samuels-razer

Razer Laptop. See [hosts README](../) for general installation steps.

| Setting | Value |
|---------|-------|
| Device | `/dev/nvme0n1` |
| Swap | 18GB |
| RAM | 16GB |
| Scale | 1.6x (HiDPI) |

```bash
# Disko
sudo nix --experimental-features "nix-command flakes" run github:nix-community/disko -- \
  --mode disko /tmp/nix/hosts/samuels-razer/disko.nix

# Install
sudo nixos-install --flake /tmp/nix#samuels-razer --no-root-passwd

# Rebuild
sudo nixos-rebuild switch --flake .#samuels-razer
```
