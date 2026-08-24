# Backgrounds

This directory contains the background assets used by the desktop theme. The
archive is kept encrypted in the repository and is decrypted locally only when
the system needs to use the configured background.

## Why encrypted?

Some of the wallpapers I use can be purchased from:

- [kram.store](https://kram.store/collections/wallpaper)
- [store.thaomaoh.com](https://store.thaomaoh.com/)

The collection contains wallpapers from various sources, not only the stores
listed above. For some images, the copyright and redistribution status is not
clear. They are included only for my personal use and stored as encrypted
binary data, so the public repository contains no usable wallpaper files and is
not intended to redistribute the artwork. If a creator would prefer a
wallpaper to be removed, please get in touch. I am happy to take it down or
work out another solution.

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
