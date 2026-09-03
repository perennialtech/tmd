# tModLoader Dedicated Server

This repository provides a tModLoader dedicated-server container and a standalone Linux management script.

Repository: <https://github.com/perennialtech/tmd>

## Supported Docker Platform

The Docker stack supports **Linux hosts only**. The published image is a `linux/amd64` image and is intended for an x86-64 Linux Docker Engine.

Windows, macOS, Docker Desktop, and native ARM64 Docker hosts are not supported. The standalone management script can use tModLoader's native Linux ARM64 support where SteamCMD is available or not required.

## Quick Links

- [Docker installation](#docker-installation)
- [Docker configuration](#docker-configuration)
- [Mods](#mods)
- [Server configuration](#server-configuration)
- [Updating Docker](#updating-docker)
- [Standalone management script](#standalone-management-script)

## Docker Installation

A new stack requires only `compose.yaml`. The image is pulled from GitHub Container Registry, and the `tModLoader` data directory is created automatically.

### Prerequisites

- An x86-64 Linux host
- Docker Engine
- Docker Compose V2, verified with:

  ```sh
  docker compose version
  ```

### Install from an empty directory

1. Create and enter a directory for the stack:

   ```sh
   mkdir tmd
   cd tmd
   ```

2. Download the Compose file:

   ```sh
   curl -fsSLO https://raw.githubusercontent.com/perennialtech/tmd/master/compose.yaml
   ```

3. Find the Linux user and group IDs that should own the server data:

   ```sh
   id -u
   id -g
   ```

4. Set `TML_UID` and `TML_GID` in `compose.yaml` to those values.

5. Pull and start the server:

   ```sh
   docker compose pull
   docker compose up -d
   ```

On first startup, Docker creates `./tModLoader`. The container assigns it to the configured identity and creates the `Mods` and `Worlds` directories.

If the server requires interactive first-run configuration, attach to its console:

```sh
docker attach tml
```

Detach without stopping the server by pressing `Ctrl-P`, followed by `Ctrl-Q`.

### Resulting files

After startup, the stack has this structure:

```text
compose.yaml
tModLoader/
├── Mods/
├── Worlds/
├── steamapps/
├── serverconfig.txt       # optional
└── tmlversion.txt         # optional modpack metadata
```

The server installation itself is supplied by the image. Persistent saves, worlds, configuration, mods, and Workshop content belong under `./tModLoader`.

## Docker Configuration

The Compose file uses these environment variables:

| Variable | Required | Default | Purpose |
| --- | --- | --- | --- |
| `TML_UID` | Yes | `1000` | Positive Linux UID used by the server process and persistent files |
| `TML_GID` | Yes | `1000` | Positive Linux GID used by the server process and persistent files |
| `UMASK` | No | `0002` | Three- or four-digit octal process umask |

Use quoted values in YAML so leading zeroes in `UMASK` are preserved:

```yaml
environment:
  TML_UID: "1000"
  TML_GID: "1000"
  UMASK: "0002"
```

`TML_UID` and `TML_GID` must:

- be canonical positive decimal integers;
- not be zero;
- not exceed `2147483647`; and
- not conflict with another account inside the image.

At every container start, ownership under `/home/tml` and `/tModLoader` is normalized to the configured IDs. This permits Docker to create the bind-mounted host directory as root while ensuring the server can write to it. It also means the configured identity becomes the owner of all existing files in `./tModLoader`.

### Ports

The server listens on TCP port `7777`. To publish another host port without changing the server port, edit the left side of the mapping:

```yaml
ports:
  - "17777:7777"
```

### Supplying server arguments in Compose

Arguments in `command` are appended to the tModLoader server launch command. This permits an unattended initial world setup without adding another deployment file. For example:

```yaml
services:
  tml:
    image: ghcr.io/perennialtech/tmd:latest
    platform: linux/amd64
    container_name: tml
    restart: unless-stopped
    environment:
      TML_UID: "1000"
      TML_GID: "1000"
      UMASK: "0002"
    command:
      - -autocreate
      - "2"
      - -world
      - /tModLoader/Worlds/world.wld
    ports:
      - "7777:7777"
    tty: true
    stdin_open: true
    volumes:
      - ./tModLoader:/tModLoader
```

Use the list form so Compose preserves argument boundaries.

## Mods

### Local mods

Place local `.tmod` files in `tModLoader/Mods`. Every enabled mod, including a local mod, must be listed in `tModLoader/Mods/enabled.json`.

### Steam Workshop mods

Steam Workshop uses numeric Workshop IDs rather than mod names. A tModLoader mod pack provides the required files:

1. In tModLoader, open **Workshop → Mod Packs**.
2. Select **Save Enabled as New Mod Pack**.
3. Select **Open Mod Pack Folder**.
4. Open the directory for the new mod pack.
5. Copy `install.txt` and `enabled.json` into `tModLoader/Mods` on the server.
6. Restart the container:

   ```sh
   docker compose restart
   ```

The container installs entries from `install.txt` at startup. No Workshop mods are downloaded when that file is absent.

## Server Configuration

For non-interactive startup, either supply server arguments in `compose.yaml` or create `tModLoader/serverconfig.txt`.

An example configuration is available from the tModLoader project:

<https://github.com/tModLoader/tModLoader/blob/1.4.5/patches/tModLoader/Terraria/release_extras/serverconfig.txt>

Important settings include:

- `worldname` sets the name used when creating a world. Do not include `.wld`.
- `world` sets the exact world path. In the container it must use a container path such as `/tModLoader/Worlds/world.wld`.
- `autocreate=1`, `autocreate=2`, or `autocreate=3` creates a small, medium, or large world when the configured world does not exist.
- `port=7777` selects the server's internal listening port. Update the Compose port mapping if this is changed.
- `maxplayers` sets the player limit.
- `password` sets the server password.

Additional settings are documented on the Terraria wiki:

<https://terraria.wiki.gg/wiki/Server#Server_config_file>

After changing `serverconfig.txt`, restart the container:

```sh
docker compose restart
```

## Server Console

View server output with:

```sh
docker compose logs -f
```

For an interactive console, use:

```sh
docker attach tml
```

Press `Ctrl-P`, followed by `Ctrl-Q`, to detach without stopping the server. Pressing `Ctrl-C` sends an interrupt to the server and can stop it.

## Updating Docker

Pull the current GHCR image and recreate the container:

```sh
docker compose pull
docker compose up -d
```

Persistent data remains in `./tModLoader`.

To inspect the running image:

```sh
docker inspect --format '{{.Config.Image}}' tml
```

The package is published at:

<https://github.com/perennialtech/tmd/pkgs/container/tmd>

## Backup

Stop the server before taking a filesystem-level backup so world files are consistent:

```sh
docker compose stop
tar czf tModLoader-backup.tar.gz tModLoader
docker compose start
```

Restore by stopping the server, replacing `./tModLoader` with the backup contents, and starting the server again. Ensure the restored files can be reassigned to the configured `TML_UID` and `TML_GID`.

## Standalone Management Script

The standalone script supports Linux installations that do not use Docker.

Download it with:

```sh
curl -fsSLO https://raw.githubusercontent.com/perennialtech/tmd/master/manage-tModLoaderServer.sh
chmod +x manage-tModLoaderServer.sh
```

Show all commands and options with:

```sh
./manage-tModLoaderServer.sh --help
```

### Standalone directory structure

```text
tModLoader/
├── Mods/
│   ├── enabled.json
│   └── install.txt
├── Worlds/
├── server/
├── steamapps/
├── manage-tModLoaderServer.sh
├── serverconfig.txt
└── tmlversion.txt
```

### Install from GitHub releases

From the data directory:

```sh
./manage-tModLoaderServer.sh install-tml --github
./manage-tModLoaderServer.sh install-mods
./manage-tModLoaderServer.sh start
```

Select a specific tModLoader release with `TMLVERSION`:

```sh
TMLVERSION=v2024.08.3.3 ./manage-tModLoaderServer.sh install-tml --github
```

### Install through SteamCMD

Ensure `steamcmd` is installed and available on `PATH`, then run:

```sh
./manage-tModLoaderServer.sh install-tml --username your_steam_username
./manage-tModLoaderServer.sh install-mods
./manage-tModLoaderServer.sh start
```

Use `STEAMCMDPATH` when SteamCMD is installed at a nonstandard path:

```sh
STEAMCMDPATH=/path/to/steamcmd.sh ./manage-tModLoaderServer.sh install-mods
```

### Update a standalone installation

Update tModLoader and installed Workshop mods with:

```sh
./manage-tModLoaderServer.sh install
```

Update only one component with either:

```sh
./manage-tModLoaderServer.sh install-tml
./manage-tModLoaderServer.sh install-mods
```

Use `--github` with `install-tml` or `install` when the installation is sourced from GitHub releases.
