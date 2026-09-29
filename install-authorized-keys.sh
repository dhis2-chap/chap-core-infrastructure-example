#!/bin/bash
set -euo pipefail

# The rebuild resets authorized_keys to the deploy key only, so re-add the
# operator keys on every deploy. Appends only keys not already present.
KEYS_FILE=configs/authorized_keys
AUTH_FILE="$HOME/.ssh/authorized_keys"

install -d -m 700 "$HOME/.ssh"
touch "$AUTH_FILE"
chmod 600 "$AUTH_FILE"

grep -vE '^\s*(#|$)' "$KEYS_FILE" | while read -r key; do
  if ! grep -qxF "$key" "$AUTH_FILE"; then
    echo "$key" >> "$AUTH_FILE"
    echo "Added operator key: ${key:0:40}..."
  fi
done
