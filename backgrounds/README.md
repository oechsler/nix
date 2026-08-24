# Wallpapers

## Why encrypted?

Some wallpapers in this collection are copyrighted images without
redistribution rights. Encryption keeps them out of the public repository while
still making them available locally; it does not replace permission to use the
images.

## Archive Flow

1. `blob.tar.gz.age` contains all wallpapers (Age encrypted)
2. The archive uses the same SSH-derived Age identity as sops-nix
3. At boot, a systemd service decrypts and extracts the archive
4. `theme.backgrounds.path` selects a filename from the extracted files

If the archive or identity is unavailable, the background module falls back to
the configured direct path or a solid color.

## Adding/editing wallpapers

```bash
# Run from this directory.
./decrypt.sh      # extracts to ./files/
# edit files in ./files/
./encrypt.sh      # re-encrypts to blob.tar.gz.age
```

`decrypt.sh` creates plaintext files locally. Run `encrypt.sh` before committing
and never commit the extracted `files/` directory.
