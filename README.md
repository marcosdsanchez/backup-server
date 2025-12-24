# Simple Arch Backup Server

A minimalist, secure backup server using [Arch Linux](https://archlinux.org/) and [Restic](https://restic.net/).
Designed for simplicity and security using standard Linux tools (SSH/SFTP).

## Features

- **Automated OS Install**: Minimal Arch Linux with `linux-lts`.
- **Secure**: Backups via SFTP (SSH) with key-based authentication.
- **Private**: Restic client-side encryption (data is encrypted before leaving the client).
- **Proactive**: Daily checks to ensure backups are running, with desktop notifications if they fail for over a week.
- **Simple**: No Docker, no complex web services. Just standard SSH.

## Quick Start

### 1. Server Setup

#### Prerequisites
- x86_64 machine (bare metal or VM).
- [Arch Linux ISO](https://archlinux.org/download/).
- Internet connection.

#### Installation
1.  **Boot** the Arch Linux ISO.
2.  **Clone** this repository:
    ```bash
    pacman -Sy git
    git clone https://github.com/YOUR_USERNAME/backup-server.git
    cd backup-server/server
    ```
3.  **Configure**:
    ```bash
    cp config.env.example config.env
    nano config.env
    ```
    *Set `DISK` (erased!), `SSH_PUBKEY` (your admin key), and passwords.*

4.  **Install**:
    ```bash
    chmod +x install-os.sh
    ./install-os.sh
    ```
    *The script will wipe the disk, install Arch, and configure a secure `backup` user.*

5.  **Reboot**:
    ```bash
    reboot
    ```

---

### 2. Client Setup

Run this on the machine you want to backup.

#### Installation
1.  **Get the client scripts**:
    Copy the `client/` directory from this repo to your machine.
    ```bash
    cd client
    ```

2.  **Configure**:
    ```bash
    cp config.env.example config.env
    nano config.env
    ```
    *Set `SERVER_HOST` (IP of your server) and `BACKUP_PATHS`.*

3.  **Install & Connect**:
    ```bash
    sudo chmod +x install-client.sh
    sudo ./install-client.sh
    ```
    *This script will:*
    - Install Restic.
    - Generate a unique SSH key for backups (if needed).
    - Give you the **Public Key**.

4.  **Authorize**:
    The client script will offer to **automatically push** the keys to the server if you have SSH access.
    
    If you need to do it **manually**:
    - **Copy the Keys** displayed by the client script.
    - **Add them to the server** using the helper scripts:
    ```bash
    # On the server (ssh root@server-ip)
    /opt/backup-server/server/add-client.sh "PASTE_BACKUP_KEY_HERE"
    /opt/backup-server/server/add-admin.sh admin "PASTE_ADMIN_KEY_HERE"
    ```

5.  **Finish**:
    Press Enter in the client script to continue. It will initialize the repository and start the backup timer.

## Usage

**Check Status**:
```bash
sudo systemctl status restic-backup.timer
```

**Run Manual Backup**:
```bash
sudo systemctl start restic-backup
```

**Check Health Monitoring**:
The system automatically checks every day if a backup has succeeded in the last 7 days. You can check the status manually:
```bash
sudo systemctl status restic-check-status.timer
# Run the check now
sudo systemctl start restic-check-status
```
If a backup hasn't run in a week, you will receive a desktop notification (via `notify-send`).

**List Snapshots**:
```bash
# Sourcing the env ensures passwords/paths are loaded
sudo -E -s
source /etc/restic/restic.env
restic snapshots
```

**Restore**:
```bash
restic restore latest --target /tmp/restore-test
```

## Security Implementation

- **OS**: Minimal Arch with `linux-lts`.
- **Transport**: SFTP over SSH (Port 22).
- **Authentication**: SSH Keys only (Password disabled for `backup` user).
- **Encryption**: Restic AES-256 (Client-side). Server sees only encrypted blobs.
- **Isolation**: Backups stored in `/srv/backups`.
