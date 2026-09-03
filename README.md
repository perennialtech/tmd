# tModLoader dedicated server

This repository provides a tModLoader dedicated-server container.

The image supports **x86-64 Linux hosts only**. It is published as `linux/amd64` and is intended for a native Linux Docker Engine.

Windows, macOS, Docker Desktop, and native ARM64 Docker hosts are not supported.

## Container image

The image is published at:

<https://github.com/perennialtech/tmd/pkgs/container/tmd>

The server installation is supplied by the image. Persistent saves, worlds, configuration, mods, and Workshop content are stored outside the image in the data directory mounted at `/tModLoader`.

On first startup, the container creates the required data directories and assigns them to the configured server identity.

```text
tModLoader/
├── Mods/
├── Worlds/
├── steamapps/
├── serverconfig.txt       # optional
└── tmlversion.txt         # optional modpack metadata
```

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

For non-interactive startup, supply server arguments as container command arguments or create `tModLoader/serverconfig.txt`.

An example configuration is available from the tModLoader project:

<https://github.com/tModLoader/tModLoader/blob/1.4.5/patches/tModLoader/Terraria/release_extras/serverconfig.txt>

Important settings include:

- `worldname` sets the name used when creating a world. Do not include `.wld`.
- `world` sets the exact world path. Use a container path such as `/tModLoader/Worlds/world.wld`.
- `autocreate=1`, `autocreate=2`, or `autocreate=3` creates a small, medium, or large world when the configured world does not exist.
- `port=7777` selects the server's internal listening port.
- `maxplayers` sets the player limit.
- `password` sets the server password.

Additional settings are documented on the Terraria wiki:

<https://terraria.wiki.gg/wiki/Server#Server_config_file>

Configuration changes take effect after the server is restarted.

## Backups

Stop the server before taking a filesystem-level backup so world files are consistent.

Back up the complete `tModLoader` data directory. When restoring it, ensure its contents can be reassigned to the configured `TML_UID` and `TML_GID`.
