FROM ubuntu:22.04 AS builder

# SteamCMD is a 32-bit x86 executable and requires glibc.
ARG DEBIAN_FRONTEND=noninteractive
RUN dpkg --add-architecture i386 \
    && apt-get update -y \
    && apt-get install -y --no-install-recommends libc6:i386 \
    && rm -rf /var/lib/apt/lists/*

FROM alpine:3.20

RUN apk add --no-cache \
        bash \
        curl \
        file \
        icu-libs \
        libgcc \
        libstdc++ \
        nano \
        su-exec

# Alpine's compatibility libraries cannot run SteamCMD reliably, so provide its
# required 32-bit glibc libraries directly.
COPY --from=builder \
    /lib/i386-linux-gnu/ld-linux.so.2 \
    /lib/i386-linux-gnu/libc.so.6 \
    /lib/i386-linux-gnu/libdl.so.2 \
    /lib/i386-linux-gnu/libm.so.6 \
    /lib/i386-linux-gnu/libpthread.so.0 \
    /lib/i386-linux-gnu/librt.so.1 \
    /lib/

ENV HOME=/home/tml \
    USER=tml \
    PATH="${PATH}:/home/tml/.bin" \
    TML_UID=1000 \
    TML_GID=1000 \
    UMASK=0002

# The image uses a fixed build identity. The entrypoint replaces these IDs with
# the configured Linux host IDs before accessing bind-mounted data.
RUN addgroup -g 1000 tml \
    && adduser -D --home /home/tml -u 1000 -G tml tml

WORKDIR /home/tml

RUN mkdir -p /home/tml/Steam /home/tml/.bin \
    && chown -R tml:tml /home/tml

USER tml

RUN curl -fsSL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" \
    | tar xzf - -C /home/tml/Steam

COPY --chown=tml:tml --chmod=0755 <<EOF /home/tml/.bin/steamcmd
#!/bin/bash

exec /home/tml/Steam/steamcmd.sh "\$@"
EOF

RUN steamcmd +quit

COPY --chown=tml:tml --chmod=0755 manage-tModLoaderServer.sh /home/tml/manage-tModLoaderServer.sh

# Install the server into the image. Persistent worlds, mods, configuration,
# workshop content, and saves are kept separately under /tModLoader.
RUN ISDOCKER=1 ./manage-tModLoaderServer.sh install-tml --github

USER root

COPY --chmod=0755 docker-entrypoint.sh /usr/local/bin/docker-entrypoint

EXPOSE 7777

ENTRYPOINT ["/usr/local/bin/docker-entrypoint"]
