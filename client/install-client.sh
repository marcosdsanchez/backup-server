#!/usr/bin/env bash
set -euo pipefail

echo ">>> Arch Linux Backup Client Setup <<<"

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Load configuration
if [ -f "config.env" ]; then
    source config.env
else
    echo "Error: config.env not found."
    exit 1
fi

# 1. Install Restic
echo "--- Installing Restic ---"
pacman -S --noconfirm restic openssh

# 2. Setup Configuration Directory
CONFIG_DIR="/etc/restic"
mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

# 3. Generate SSH Key for Backups if it doesn't exist
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "--- Generating SSH Key for Backups ---"
    mkdir -p "$(dirname "$SSH_KEY_PATH")"
    ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N ""
fi

PUB_KEY=$(cat "${SSH_KEY_PATH}.pub")

if [ -z "$SERVER_IP" ]; then
    read -p "Enter Backup Server IP or Hostname: " SERVER_IP
fi

echo ""
echo "=================================================================="
echo "ACTION REQUIRED: Add the following public key to the SERVER."
echo "Run this command on the SERVER (as root):"
echo "   /path/to/server/add-client-key.sh '$PUB_KEY'"
echo "=================================================================="
echo ""
read -p "Press 'y' when you have added the key to the server to continue... " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborting."
    exit 1
fi

# 4. Configure Restic Environment
REPO_URL="sftp:backup@${SERVER_IP}:/backups/client-$(hostname)"
ENV_FILE="$CONFIG_DIR/restic.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "--- Configuring Restic Environment ---"
    read -s -p "Enter a NEW encryption password for the Restic repository: " RESTIC_PASSWORD
    echo ""
    read -s -p "Confirm password: " RESTIC_PASSWORD_CONFIRM
    echo ""
    
    if [ "$RESTIC_PASSWORD" != "$RESTIC_PASSWORD_CONFIRM" ]; then
        echo "Passwords do not match!"
        exit 1
    fi

    cat <<EOF > "$ENV_FILE"
RESTIC_REPOSITORY=$REPO_URL
RESTIC_PASSWORD=$RESTIC_PASSWORD
RESTIC_SSH_COMMAND="ssh -i $SSH_KEY_PATH -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
BACKUP_PATHS="$BACKUP_PATHS"
KEEP_DAILY=$KEEP_DAILY
KEEP_WEEKLY=$KEEP_WEEKLY
KEEP_MONTHLY=$KEEP_MONTHLY
EOF
    chmod 600 "$ENV_FILE"
else
    echo "--- $ENV_FILE already exists, skipping ---"
fi

# 5. Initialize Repository
echo "--- Initializing Restic Repository ---"
export $(grep -v '^#' "$ENV_FILE" | xargs)
if restic snapshots > /dev/null 2>&1; then
    echo "Repository already initialized."
else
    restic init
fi

# 6. Install Systemd Units
echo "--- Installing Systemd Units ---"
# We'll use a template for the timer to use BACKUP_ON_CALENDAR
sed "s/OnCalendar=.*/OnCalendar=$BACKUP_ON_CALENDAR/" restic-backup.timer > /etc/systemd/system/restic-backup.timer
cp restic-backup.service /etc/systemd/system/
cp restic-prune.service /etc/systemd/system/
cp restic-prune.timer /etc/systemd/system/

systemctl daemon-reload

# 7. Enable Timers
echo "--- Enabling Timers ---"
systemctl enable --now restic-backup.timer
systemctl enable --now restic-prune.timer

echo "✅ Client Setup Complete!"
