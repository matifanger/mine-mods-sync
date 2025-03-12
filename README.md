# Minecraft Mod Sync

Simple tool to keep Minecraft mods in sync between server and clients.

[.github/image.png]

## Environment Variables

Copy `.env.example` to `.env` and configure your variables:

### Required Variables
- `MODS_DIR`: Full path to the mods directory
  - Development example: `./mods`
  - Production example (linux): `/data/services/minecraft-data/mods`

## Server Setup

1. Make sure Docker and Docker Compose are installed
2. Clone this repository
3. Copy environment file:
```bash
cp .env.example .env
```
4. Edit `.env` and set your variables
5. Run:
```bash
docker-compose up -d
```

## Client Setup

### PowerShell Script Configuration

The script has two configuration switches at the top:

```powershell
$DEV_URL = "http://localhost:8000" # Local server url for testing
$PROD_URL = "YOUR SERVER URL" # Your app.py server url
$READ_ONLY = $true # Only allow downloading mods (use false to be able to upload mods to the server)
$FORCE_PROD = $false # Switch to force production mode (use true when not testing)
```

### Installation

1. Download `sync-mods.ps1` to your computer. You can share this to friends, so they can update their mods lists automatically with the server.

```
2. Run the script:
```powershell
.\sync-mods.ps1
```

The script will:
- Ask for your Minecraft mods folder location
- Save the location for future use
- Download/sync mods from the server

### Notes

- The script automatically detects your Minecraft mods folder
- It only syncs `.jar` files
- When downloading, it only updates mods that are new or modified
- The server URL is saved in `sync-config.json` next to the script
- In read-only mode (default), users can only download mods
- In production mode (default), development mode selection is disabled 