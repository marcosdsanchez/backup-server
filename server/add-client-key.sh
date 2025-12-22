#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <client_rsa_pub_key_string>"
    echo "Example: $0 'ssh-ed25519 AAAA...'"
    exit 1
fi

CLIENT_KEY="$1"
AUTH_KEYS_FILE="/backups/.ssh/authorized_keys"

# Validate that we are running as root (needed to modify backup user files)
if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root"
  exit 1
fi

if [ ! -f "$AUTH_KEYS_FILE" ]; then
    echo "Error: $AUTH_KEYS_FILE not found. Is the backup user configured?"
    exit 1
fi

# The restricted command that forces restic serve in stdio mode
RESTRICTION="command=\"restic serve --stdio --restrict-to-path /backups\",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty"

# Check if key already exists to avoid duplicates (simple grep)
if grep -qF "$CLIENT_KEY" "$AUTH_KEYS_FILE"; then
    echo "Key already exists in $AUTH_KEYS_FILE"
else
    echo "$RESTRICTION $CLIENT_KEY" >> "$AUTH_KEYS_FILE"
    echo "✅ Key added successfully."
fi
