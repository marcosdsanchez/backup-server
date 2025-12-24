#!/usr/bin/env bash

# Load restic environment
if [ -f /etc/restic/restic.env ]; then
    source /etc/restic/restic.env
else
    echo "Restic environment file not found at /etc/restic/restic.env"
    exit 1
fi

# Get the last snapshot time in seconds since epoch
LAST_SNAPSHOT_JSON=$(restic snapshots --last --json)
LAST_SNAPSHOT_TIME=$(echo "$LAST_SNAPSHOT_JSON" | grep -oP '"time":"\K[^"]+' | head -n 1)

if [ -z "$LAST_SNAPSHOT_TIME" ]; then
    echo "No snapshots found."
    LAST_SNAPSHOT_DATE="Never"
    SHOULD_NOTIFY=true
else
    # Parse date to seconds. Restic uses RFC3339: 2025-12-24T15:59:36.123456789-03:00
    # We can use 'date' to convert it
    LAST_SNAPSHOT_EPOCH=$(date -d "$LAST_SNAPSHOT_TIME" +%s)
    CURRENT_EPOCH=$(date +%s)
    DIFF=$(( (CURRENT_EPOCH - LAST_SNAPSHOT_EPOCH) / 86400 )) # Difference in days
    
    LAST_SNAPSHOT_DATE=$(date -d "$LAST_SNAPSHOT_TIME" "+%Y-%m-%d %H:%M")

    if [ "$DIFF" -ge 7 ]; then
        SHOULD_NOTIFY=true
    else
        SHOULD_NOTIFY=false
        echo "Last backup was $DIFF days ago ($LAST_SNAPSHOT_DATE). All good."
    fi
fi

if [ "$SHOULD_NOTIFY" = true ]; then
    MESSAGE="Warning: No successful backup in the last week! Last backup: $LAST_SNAPSHOT_DATE"
    echo "$MESSAGE"
    
    # Send notification to all logged-in users with a display
    for user in $(users | tr ' ' '\n' | sort -u); do
        USER_ID=$(id -u "$user")
        # Try to find the DBUS_SESSION_BUS_ADDRESS for the user
        DBUS_ADDRESS="unix:path=/run/user/$USER_ID/bus"
        
        if [ -S "/run/user/$USER_ID/bus" ]; then
            sudo -u "$user" DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDRESS" \
                notify-send "Backup Alert" "$MESSAGE" --icon=dialog-warning
        fi
    done
fi
