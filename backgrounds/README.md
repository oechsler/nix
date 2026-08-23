# Wallpapers

## Why encrypted?

Some wallpapers in this collection are copyrighted images I don't have
redistribution rights for. To keep this repo public while still using these
images locally, they're stored in an encrypted archive.

## Archive Flow

1. `blob.tar.gz.age` contains all wallpapers (Age encrypted)
2. The archive uses the same SSH-derived Age identity as sops-nix
3. At boot, a systemd service decrypts and extracts the archive
4. `theme.backgrounds.path` in host configs is just the filename inside the archive

## Adding/editing wallpapers

```bash
./decrypt.sh      # extracts to ./files/
                  # edit files in ./files/
./encrypt.sh      # re-encrypts to blob.tar.gz.age
```
