# tModLoader dedicated server

This repository provides a tModLoader dedicated-server container and a standalone Linux management script.

The Docker image supports **x86-64 Linux hosts only**. It is published as `linux/amd64` and is intended for a native Linux Docker Engine.

Windows, macOS, Docker Desktop, and native ARM64 Docker hosts are not supported.

The standalone management script supports Linux and can use tModLoader's native Linux ARM64 release when SteamCMD is available or is not required.

## Docker deployment

The Docker deployment is defined in [`compose.yaml`](./compose.yaml) and uses the image published at:

<https://github.com/perennialtech/tmd/pkgs/container/tmd>

The server installation is supplied by the image. Persistent saves, worlds, configuration, mods, and Workshop content are stored in the host's `./tModLoader` directory.

On first startup, the container creates the required data directories and assigns them to the configured server identity.

```text
tModLoader/
├── Mods/
├── Worlds/
├── steamapps/
├── serverconfig.txt       # optional
└── tmlversion.txt         # optional modpack metadata
```

## Docker configuration

Configure the following environment variables in [`compose.yaml`](./compose.yaml):

| Variable  | Default | Purpose                                                            |
| --------- | ------- | ------------------------------------------------------------------ |
| `TML_UID` | `1000`  | Positive Linux UID used by the server process and persistent files |
| `TML_GID` | `1000`  | Positive Linux GID used by the server process and persistent files |
| `UMASK`   | `0002`  | Three- or four-digit octal process umask                           |

Quote these values in YAML so the leading zeroes in `UMASK` are preserved.

`TML_UID` and `TML_GID` must:

- be canonical positive decimal integers;
- not be zero;
- not exceed `2147483647`; and
- not conflict with another account inside the image.

At every container start, ownership under `/home/tml` and `/tModLoader` is normalized to the configured IDs. The configured identity therefore becomes the owner of all existing files in `./tModLoader`.

The server listens on TCP port `7777` by default. If the internal server port is changed, the port mapping in [`compose.yaml`](./compose.yaml) must be updated accordingly.

Additional tModLoader server arguments can be supplied through the service's `command` value. Use YAML list form so argument boundaries are preserved. Container paths, such as `/tModLoader/Worlds/world.wld`, must be used for files inside the persistent data directory.

## Mods

### Local mods

Place local `.tmod` files in `tModLoader/Mods`.

Every enabled mod, including each local mod, must be listed in `tModLoader/Mods/enabled.json`.

### Steam Workshop mods

Steam Workshop uses numeric Workshop IDs rather than mod names. A tModLoader mod pack provides the required metadata:

1. In tModLoader, open **Workshop → Mod Packs**.
2. Select **Save Enabled as New Mod Pack**.
3. Select **Open Mod Pack Folder**.
4. Open the directory for the new mod pack.
5. Copy `install.txt` and `enabled.json` into `tModLoader/Mods` on the server.
6. Restart the server.

The container installs entries from `install.txt` during startup. No Workshop mods are downloaded when that file is absent.

## Server configuration

For non-interactive startup, either supply server arguments through [`compose.yaml`](./compose.yaml) or create `tModLoader/serverconfig.txt`.

An example configuration is available from the tModLoader project:

<https://github.com/tModLoader/tModLoader/blob/1.4.5/patches/tModLoader/Terraria/release_extras/serverconfig.txt>

Important settings include:

- `worldname` sets the name used when creating a world. Do not include `.wld`.
- `world` sets the exact world path. Docker deployments must use a container path such as `/tModLoader/Worlds/world.wld`.
- `autocreate=1`, `autocreate=2`, or `autocreate=3` creates a small, medium, or large world when the configured world does not exist.
- `port=7777` selects the server's internal listening port.
- `maxplayers` sets the player limit.
- `password` sets the server password.

Additional settings are documented on the Terraria wiki:

<https://terraria.wiki.gg/wiki/Server#Server_config_file>

Configuration changes take effect after the server is restarted.

## Backups

Stop the server before taking a filesystem-level backup so world files are consistent.

Back up the complete `tModLoader` directory. When restoring it, ensure its contents can be reassigned to the configured `TML_UID` and `TML_GID`.

## Standalone management script

[`manage-tModLoaderServer.sh`](./manage-tModLoaderServer.sh) supports Linux installations that do not use Docker.

Place the script in the intended tModLoader data directory:

```sh
curl -fsSLO https://raw.githubusercontent.com/perennialtech/tmd/master/manage-tModLoaderServer.sh
```

Show all commands and options with:

```sh
./manage-tModLoaderServer.sh --help
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
