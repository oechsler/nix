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

## Adding/editing wallpapers

```bash
./decrypt.sh      # extracts to ./files/
                  # edit files in ./files/
./encrypt.sh      # re-encrypts to blob.tar.gz.enc
```
