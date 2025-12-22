# Headless Restic Backup Server

A collection of scripts to set up a dedicated, encrypted Arch Linux backup server and automated clients using [Restic](https://restic.net/).

## Features

- **Encrypted Server**: Full disk encryption (LUKS) with remote SSH unlock (via dropbear/mkinitcpio-netconf).
- **Headless Design**: 100% headless after initial install.
- **Secure Access**: Backups are performed over SSH using a restricted `restic serve` subprocess, meaning clients cannot access a full shell or other backup data.
- **Automated Clients**: Systemd services and timers for automated daily backups and weekly pruning.
- **Configurable**: Easy configuration via environment files.

## Project Structure

- `server/`: Scripts for the backup server.
  - `install.sh`: OS installation script (to be run from an Arch Netboot/ISO).
  - `config.env`: Configuration for the OS install (Disk, Hostname, SSH Keys).
  - `add-client-key.sh`: Helper to authorize a new client's backup key.
- `client/`: Scripts for the machines being backed up.
  - `install-client.sh`: Automated setup for the client.
  - `config.env`: Client-specific configuration (Backup paths, server IP).
  - `*.service/timer`: Systemd units for automation.

## Prerequisites

- **Server**: A machine/VM for the backup server with an Ethernet connection.
- **Client**: Any Arch Linux machine. (Scripts can be adapted for other distros).

## Getting Started

### 1. Server Setup

1. Boot the server with the Arch Linux ISO.
2. Ensure you have network access (Ethernet with DHCP is assumed).
3. Clone this repository or download the `server/` directory.
4. Edit `server/config.env` with your desired settings (especially `SSH_PUBKEY`).
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
2. Edit `client/config.env` to specify what paths to backup.
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
