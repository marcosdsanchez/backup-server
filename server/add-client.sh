#!/usr/bin/env bash
set -euo pipefail

# server/add-client.sh
# Adds a restic backup public key to the restricted backup user.

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

BACKUP_USER="backup"
AUTHORIZED_KEYS="/srv/backups/.ssh/authorized_keys"

if [ $# -lt 1 ]; then
    echo "Usage: $0 \"ssh-ed25519 AAA... user@host\""
    echo "Alternatively, pipe the key into this script."
fi

# Get key from argument or stdin
NEW_KEY="${1:-$(cat /dev/stdin)}"

if [ -z "$NEW_KEY" ]; then
    echo "Error: No key provided."
    exit 1
fi

# Check if key already exists
BACKUP_SSH_DIR="$(dirname "$AUTHORIZED_KEYS")"
mkdir -p "$BACKUP_SSH_DIR"
chmod 700 "$BACKUP_SSH_DIR"

if grep -qF "$NEW_KEY" "$AUTHORIZED_KEYS" 2>/dev/null; then
    echo "Key already authorized. Skipping."
else
    echo "Adding key to $BACKUP_USER..."
    echo "$NEW_KEY" >> "$AUTHORIZED_KEYS"
    chown -R backup:backup "$BACKUP_SSH_DIR"
    chmod 600 "$AUTHORIZED_KEYS"
    echo "✅ Key added successfully."
fi
