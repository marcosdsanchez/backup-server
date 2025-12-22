# Headless Restic Backup Server

A collection of scripts to set up a dedicated, encrypted Arch Linux backup server and automated clients using [Restic](https://restic.net/).

## Features

- **Encrypted Server**: Full disk encryption (LUKS) with remote SSH unlock (via dropbear/mkinitcpio-netconf).
- **Headless Design**: 100% headless after initial install.
- **Secure Access**: Backups are performed over SSH using a restricted `restic serve` subprocess, meaning clients cannot access a full shell or other backup data.
- **Automated Clients**: Systemd services and timers for automated daily backups and weekly pruning.
- **Configurable**: Easy configuration via environment files.

## Quick Start Guide

Setting up your backup system in 5 easy steps:

1. **Configure Server**: Copy `server/config.env.example` to `config.env` and edit it with your SSH key and preferred disk.
2. **Install Server**: Boot server machine with Arch ISO and run `server/install.sh`.
3. **Unlock & Connect**: Reboot server, unlock via SSH `cryptroot-unlock`, and note its IP.
4. **Configure Client**: Copy `client/config.env.example` to `config.env` and edit it with the server's IP and paths to back up.
5. **Install Client**: Run `client/install-client.sh` on the machine you want to backup.

---

## Project Structure

- `server/`: Scripts for the backup server appliance.
  - `install.sh`: OS installation script.
  - `config.env`: Build configuration.
  - `add-client-key.sh`: Authorize a new client.
- `client/`: Automation for client machines.
  - `install-client.sh`: Client setup script.
  - `config.env`: Paths and schedule configuration.

## Prerequisites

- **Server**: Hardware or VM with Ethernet (DHCP).
- **Client**: Arch Linux (or compatible).


## Getting Started

### 1. Server Setup

1. Boot the server with the Arch Linux ISO.
2. Ensure you have network access (Ethernet with DHCP is assumed).
3. Clone this repository or download the `server/` directory.
4. Copy `config.env.example` to `config.env` and edit it with your desired settings (especially `SSH_PUBKEY`).
5. Run the installer:
   ```bash
   cd server
   chmod +x install.sh
   ./install.sh
   ```
6. Reboot. You can now unlock the disk remotely:
   ```bash
   ssh root@server-ip "cryptroot-unlock"
   ```

### 2. Client Setup

1. Copy the `client/` directory to the target machine.
2. Copy `config.env.example` to `config.env` and edit it to specify what paths to backup.
3. Run the installer as root:
   ```bash
   cd client
   chmod +x install-client.sh
   ./install-client.sh
   ```
4. Follow the instructions to add the client's public key to the server using `add-client-key.sh`.

## Security

- **Encryption**: The server uses LUKS for data at rest.
- **Isolation**: The `backup` user on the server has no login shell and is restricted to the `/backups` directory via the SSH `command` restriction.
- **Privacy**: Each client typically gets its own subdirectory (e.g., `/backups/client-hostname`).

## License

MIT
