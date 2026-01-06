#!/usr/bin/env bash
set -euo pipefail

echo ">>> Restic Backup Client Setup <<<"

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# Load configuration
if [ -f "config.env" ]; then
    source config.env
else
    echo "NO config.env found. Running interactive setup..."
fi

# =============================================================================
# 1. INSTALL RESTIC
# =============================================================================
echo "--- Installing Restic ---"
if command -v pacman &> /dev/null; then
    pacman -S --noconfirm --needed restic openssh libnotify
elif command -v apt-get &> /dev/null; then
    apt-get update && apt-get install -y restic openssh-client libnotify-bin
elif command -v dnf &> /dev/null; then
    dnf install -y restic openssh-clients libnotify
else
    echo "Unknown package manager. Please install restic and libnotify manually."
    exit 1
fi

# =============================================================================
# 2. CONFIGURE CONNECTION (SFTP)
# =============================================================================
echo "--- Configuring Connection ---"

if [ -z "${SERVER_HOST:-}" ]; then
    read -p "Enter Backup Server IP/Hostname: " SERVER_HOST
fi

# A. Automated Backup Key (ROOT)
SSH_KEY="/root/.ssh/id_backup_ed25519"
if [ ! -f "$SSH_KEY" ]; then
    echo "Generating SSH key for automated backups..."
    mkdir -p /root/.ssh
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -q
fi

# root SSH config for automated service
SSH_CONFIG_ROOT="/root/.ssh/config"
if ! grep -q "Host backup-server" "$SSH_CONFIG_ROOT" 2>/dev/null; then
    cat <<EOF >> "$SSH_CONFIG_ROOT"

Host backup-server
    HostName $SERVER_HOST
    User backup
    IdentityFile $SSH_KEY
    StrictHostKeyChecking accept-new
EOF
    chmod 600 "$SSH_CONFIG_ROOT"
fi

# B. Manual Access for Local User (e.g. local_user -> server_admin)
if [ -n "${SUDO_USER:-}" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    read -p "Enter admin username on server [admin]: " SERVER_ADMIN
    SERVER_ADMIN="${SERVER_ADMIN:-admin}"
    
    USER_SSH_CONFIG="$USER_HOME/.ssh/config"
    mkdir -p "$USER_HOME/.ssh"
    chown "$SUDO_USER:$SUDO_USER" "$USER_HOME/.ssh"
    
    if ! grep -q "Host backup-server-admin" "$USER_SSH_CONFIG" 2>/dev/null; then
        echo "Configuring manual SSH shortcut (ssh backup-server-admin) for $SUDO_USER..."
        cat <<EOF >> "$USER_SSH_CONFIG"

Host $SERVER_HOST-admin
    HostName $SERVER_HOST
    User $SERVER_ADMIN
    StrictHostKeyChecking accept-new
EOF
        chown "$SUDO_USER:$SUDO_USER" "$USER_SSH_CONFIG"
        chmod 600 "$USER_SSH_CONFIG"
    fi

    # Find local user's public key (check common names)
    USER_PUB_KEY=""
    USER_KEY_PATH=""
    for k in "$USER_HOME"/.ssh/id_{ed25519,rsa,ecdsa}.pub; do
        if [ -f "$k" ]; then
            USER_PUB_KEY=$(cat "$k")
            USER_KEY_PATH="${k%.pub}"
            break
        fi
    done
    
    # If still not found, create a new one for the user
    if [ -z "$USER_PUB_KEY" ]; then
        echo "No personal SSH key found for $SUDO_USER. Generating one..."
        USER_KEY_PATH="$USER_HOME/.ssh/id_ed25519"
        # Generate as the actual user
        sudo -u "$SUDO_USER" ssh-keygen -t ed25519 -f "$USER_KEY_PATH" -N "" -q
        USER_PUB_KEY=$(cat "${USER_KEY_PATH}.pub")
    fi
fi

echo ""
echo "--- Key Authorization ---"
echo "To finish setup, your keys must be authorized on the server."

# Detection for automatic push
PUSH_SUCCESS=false
if [ -n "${SERVER_HOST:-}" ]; then
    echo "Checking if we can reach the server to authorize automatically..."
    # Check if we can SSH as root or admin
    TARGET_USER="root"
    if ! ssh -o ConnectTimeout=3 -o BatchMode=yes -o StrictHostKeyChecking=accept-new "${TARGET_USER}@${SERVER_HOST}" "true" 2>/dev/null; then
        TARGET_USER="${SERVER_ADMIN:-admin}"
        if ! ssh -o ConnectTimeout=3 -o BatchMode=yes -o StrictHostKeyChecking=accept-new "${TARGET_USER}@${SERVER_HOST}" "true" 2>/dev/null; then
            TARGET_USER=""
        fi
    fi

    if [ -n "$TARGET_USER" ]; then
        read -p "Connection to server ($TARGET_USER) found. Push keys automatically? [Y/n]: " DO_PUSH
        if [[ ! "$DO_PUSH" =~ ^[Nn] ]]; then
            echo "Pushing backup key..."
            # If we are admin, we need sudo on the server
            SUDO_PREFIX=""
            [ "$TARGET_USER" != "root" ] && SUDO_PREFIX="sudo "
            
            if cat "${SSH_KEY}.pub" | ssh "${TARGET_USER}@${SERVER_HOST}" "${SUDO_PREFIX}/opt/backup-server/server/add-client.sh"; then
                if [ -n "${USER_PUB_KEY:-}" ]; then
                    echo "Pushing your personal key..."
                    ssh "${TARGET_USER}@${SERVER_HOST}" "${SUDO_PREFIX}/opt/backup-server/server/add-admin.sh $SERVER_ADMIN \"$USER_PUB_KEY\""
                fi
                PUSH_SUCCESS=true
                echo "✅ Keys pushed and authorized!"
            else
                echo "❌ Failed to push keys automatically."
            fi
        fi
    fi
fi

if [ "$PUSH_SUCCESS" = false ]; then
    echo ""
    echo "ACTION REQUIRED: Manual Authorization"
    echo "---------------------------------------------------------------------------------"
    echo "1. KEY FOR AUTOMATED BACKUPS (Copy this):"
    cat "${SSH_KEY}.pub"
    echo ""
    if [ -n "${USER_PUB_KEY:-}" ]; then
        echo "2. YOUR PERSONAL KEY (Copy this for admin access):"
        echo "$USER_PUB_KEY"
        echo ""
        echo "Manual Instructions:"
        echo "  - SSH into the server as root: ssh root@$SERVER_HOST"
        echo "  - Run: /opt/backup-server/server/add-client.sh \"PASTE_KEY_1_HERE\""
        echo "  - Run: /opt/backup-server/server/add-admin.sh $SERVER_ADMIN \"PASTE_KEY_2_HERE\""
    else
        echo "Note: No local public key found for $SUDO_USER. Please authorize your personal key on the server manually."
    fi
    echo "---------------------------------------------------------------------------------"
    echo ""
    read -p "Press Enter once you have added the keys to the server..."
fi

# =============================================================================
# 3. CONFIGURE RESTIC
# =============================================================================
CONFIG_DIR="/etc/restic"
mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"
ENV_FILE="$CONFIG_DIR/restic.env"
HOSTNAME_SHORT=$(hostname)

# The repo URL should use the 'backup-server' alias we defined in SSH config.
# This ensures that Restic uses the correct IdentityFile and User.
# Path is relative to the backup user's home (/srv/backups)
REPO_URL="sftp:backup-server:client-$HOSTNAME_SHORT"

echo "--- Configuring Restic Environment ---"

if [ -f "$ENV_FILE" ]; then
    echo "Found existing configuration at $ENV_FILE."
    read -p "Overwrite with new settings? [Y/n]: " OVERWRITE_ENV
    if [[ "$OVERWRITE_ENV" =~ ^[Nn] ]]; then
        echo "Using existing configuration."
        # Load existing config to get RESTIC_PASSWORD if needed
        source "$ENV_FILE"
    else
        rm "$ENV_FILE"
    fi
fi

if [ ! -f "$ENV_FILE" ]; then
    if [ -z "${RESTIC_PASSWORD:-}" ]; then
        while true; do
            read -s -p "Enter a NEW encryption password for the Restic repository: " RESTIC_PASSWORD
            echo ""
            read -s -p "Confirm password: " RESTIC_PASSWORD_CONFIRM
            echo ""
            [ "$RESTIC_PASSWORD" = "$RESTIC_PASSWORD_CONFIRM" ] && break
            echo "Passwords do not match. Try again."
        done
    else
        echo "Using existing RESTIC_PASSWORD."
    fi

    # Default paths if not set
    BACKUP_PATHS="${BACKUP_PATHS:-/etc /home}"
    KEEP_DAILY="${KEEP_DAILY:-7}"
    KEEP_WEEKLY="${KEEP_WEEKLY:-4}"
    KEEP_MONTHLY="${KEEP_MONTHLY:-6}"
    BACKUP_ON_CALENDAR="${BACKUP_ON_CALENDAR:-*-*-* 03:00:00}"

    cat <<EOF > "$ENV_FILE"
RESTIC_REPOSITORY="$RESTIC_REPOSITORY"
RESTIC_PASSWORD="$RESTIC_PASSWORD"
RESTIC_CACHE_DIR="/root/.cache/restic"
BACKUP_PATHS="$BACKUP_PATHS"
KEEP_DAILY="$KEEP_DAILY"
KEEP_WEEKLY="$KEEP_WEEKLY"
KEEP_MONTHLY="$KEEP_MONTHLY"
EOF
    chmod 600 "$ENV_FILE"

    # Create excludes file if it doesn't exist
    EXCLUDES_FILE="$CONFIG_DIR/excludes.txt"
    if [ ! -f "$EXCLUDES_FILE" ]; then
        cat <<EOF > "$EXCLUDES_FILE"
# Add files/folders to exclude here, one per line
# Example:
# /home/*/.cache
# /home/*/.local/share/Trash
EOF
        chmod 600 "$EXCLUDES_FILE"
    fi
    echo "Configured $ENV_FILE and $EXCLUDES_FILE"
fi

# =============================================================================
# 4. INITIALIZE REPOSITORY
# =============================================================================
echo "--- Initializing Restic Repository ---"
set -a
source "$ENV_FILE"
set +a

if restic -r "$RESTIC_REPOSITORY" snapshots > /dev/null 2>&1; then
    echo "Repository already initialized."
else
    echo "Initializing new repository at $RESTIC_REPOSITORY"
    if restic -r "$RESTIC_REPOSITORY" init; then
        echo "Repository initialized successfully."
    else
        echo "Failed to initialize repository. Check SSH connection and permissions."
        exit 1
    fi
fi

# =============================================================================
# 5. INSTALL SYSTEMD UNITS
# =============================================================================
echo "--- Installing Systemd Units ---"
# We need to ensure we have the service files locally or create them
# Assuming they are in the current directory as before

if [ -f "restic-backup.timer" ]; then
    sed "s/OnCalendar=.*/OnCalendar=$BACKUP_ON_CALENDAR/" restic-backup.timer > /etc/systemd/system/restic-backup.timer
    cp restic-backup.service /etc/systemd/system/
    
    # Prune service (optional check if file exists)
    [ -f "restic-prune.service" ] && cp restic-prune.service /etc/systemd/system/
    [ -f "restic-prune.timer" ] && cp restic-prune.timer /etc/systemd/system/

    # Status check service
    if [ -f "restic-check-status.sh" ]; then
        cp restic-check-status.sh /usr/local/bin/
        chmod +x /usr/local/bin/restic-check-status.sh
        cp restic-check-status.service /etc/systemd/system/
        cp restic-check-status.timer /etc/systemd/system/
    fi

    # Excludes file
    if [ -f "excludes.txt" ]; then
        cp excludes.txt /etc/restic/
        chmod 600 /etc/restic/excludes.txt
    fi
    
    systemctl daemon-reload
    systemctl enable --now restic-backup.timer
    [ -f "restic-prune.timer" ] && systemctl enable --now restic-prune.timer
    [ -f "restic-check-status.timer" ] && systemctl enable --now restic-check-status.timer
else
    echo "Warning: restic-backup.timer not found in current directory."
    echo "Systemd services were NOT installed."
fi

echo ""
echo "✅ Client Setup Complete!"
echo "Manual backup:  sudo systemctl start restic-backup"
echo "View status:    sudo systemctl status restic-backup.timer"
