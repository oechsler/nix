# Wallpapers

## Why encrypted?

Some wallpapers in this collection are copyrighted images I don't have
redistribution rights for. To keep this repo public while still using these
images locally, they're stored in an encrypted archive.

## How it works

1. `blob.tar.gz.enc` contains all wallpapers (AES-256 encrypted)
2. The password is stored in `sops/sops.encrypted.yaml` under `backgrounds/password`
3. At boot, a systemd service decrypts and extracts the archive
4. `theme.wallpaper` in host configs is just the filename inside the archive

## Runtime paths

- `/var/lib/backgrounds/` - extracted wallpapers
- `/var/lib/backgrounds/current.jpg` - selected wallpaper (converted to jpg)
- `/var/lib/backgrounds/current-blurred.jpg` - blurred version for SDDM

## Adding wallpapers

```bash
# Decrypt, add, re-encrypt
openssl enc -d -aes-256-cbc -pbkdf2 -pass pass:PASSWORD < blob.tar.gz.enc | tar xzf -
tar czf - *.png *.jpg | openssl enc -aes-256-cbc -pbkdf2 -pass pass:PASSWORD > blob.tar.gz.enc
rm *.png *.jpg
```

## Fallback

Hosts without `backgrounds.enable = true` can still use regular paths:

```nix
theme.wallpaper = ../../backgrounds/some-free-image.png;
```
