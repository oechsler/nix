#!/usr/bin/env nix-shell
#!nix-shell -i bash -p openssl gzip gnutar

set -euo pipefail
cd "$(dirname "$0")"

read -rsp "Password: " PASSWORD
echo

mkdir -p files
openssl enc -d -aes-256-cbc -pbkdf2 -pass pass:"$PASSWORD" < blob.tar.gz.enc | gzip -d | tar xf - -C files

echo "Decrypted to ./files/"
