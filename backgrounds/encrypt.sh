#!/usr/bin/env nix-shell
#!nix-shell -i bash -p openssl gzip gnutar

set -euo pipefail
cd "$(dirname "$0")"

if [ ! -d files ] || [ -z "$(ls -A files)" ]; then
  echo "Error: ./files/ is empty or does not exist"
  exit 1
fi

read -rsp "Password: " PASSWORD
echo

tar cf - -C files . | gzip | openssl enc -aes-256-cbc -pbkdf2 -pass pass:"$PASSWORD" > blob.tar.gz.enc

echo "Encrypted ./files/ to blob.tar.gz.enc"
