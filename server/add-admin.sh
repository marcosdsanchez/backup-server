#!/usr/bin/env bash
set -euo pipefail

# server/add-admin.sh
# Adds a personal public key to an admin user's authorized_keys.

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

if [ $# -lt 2 ]; then
    echo "Usage: $0 <username> \"ssh-ed25519 AAA...\""
    exit 1
fi

ADMIN_USER="$1"
NEW_KEY="$2"

if ! id "$ADMIN_USER" &>/dev/null; then
    echo "Error: User $ADMIN_USER does not exist."
    exit 1
fi

USER_HOME=$(getent passwd "$ADMIN_USER" | cut -d: -f6)
AUTH_FILE="$USER_HOME/.ssh/authorized_keys"

mkdir -p "$USER_HOME/.ssh"
chmod 700 "$USER_HOME/.ssh"
touch "$AUTH_FILE"
chmod 600 "$AUTH_FILE"

if grep -qF "$NEW_KEY" "$AUTH_FILE" 2>/dev/null; then
    echo "Key already authorized for $ADMIN_USER."
else
    echo "Adding key for $ADMIN_USER..."
    echo "$NEW_KEY" >> "$AUTH_FILE"
    chown -R "$ADMIN_USER:$ADMIN_USER" "$USER_HOME/.ssh"
    echo "✅ Key added successfully."
fi
