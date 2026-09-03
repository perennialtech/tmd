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
        su-exec \
        unzip \
        util-linux

# Copy the complete i386 glibc directory so that library symlinks and their
# versioned targets remain consistent.
COPY --from=builder /lib/i386-linux-gnu/ /lib/

ENV HOME=/home/tml \
    USER=tml \
    PATH="${PATH}:/home/tml/.bin" \
    TML_UID=1000 \
    TML_GID=1000 \
    TML_WORKSHOP_IDS="" \
    UMASK=0002

# The image uses a fixed build identity. The entrypoint replaces these IDs with
# the configured Linux host IDs before accessing bind-mounted data.
RUN addgroup -g 1000 tml \
    && adduser -D --home /home/tml -u 1000 -G tml tml

WORKDIR /home/tml

RUN mkdir -p /home/tml/Steam /home/tml/.bin \
    && chown -R tml:tml /home/tml

USER tml

RUN curl -fL \
        -o /tmp/steamcmd-linux.tar.gz \
        "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" \
    && tar -xzf /tmp/steamcmd-linux.tar.gz -C /home/tml/Steam \
    && rm -f /tmp/steamcmd-linux.tar.gz

COPY --chown=tml:tml --chmod=0755 <<EOF /home/tml/.bin/steamcmd
#!/bin/bash

exec /home/tml/Steam/steamcmd.sh "\$@"
EOF

RUN steamcmd +quit

COPY --chown=tml:tml --chmod=0755 manage-tModLoaderServer.sh /home/tml/manage-tModLoaderServer.sh

# The exact release is resolved outside the Docker build so a changed upstream
# version changes this layer's cache key.
ARG TML_VERSION
RUN test -n "$TML_VERSION" \
    && ISDOCKER=1 TMLVERSION="$TML_VERSION" \
        ./manage-tModLoaderServer.sh install-tml --github \
    && test -f /home/tml/server/LaunchUtils/ScriptCaller.sh \
    && chmod 0755 /home/tml/server/LaunchUtils/ScriptCaller.sh

LABEL io.github.perennialtech.tmd.tmodloader-version="$TML_VERSION"

USER root

COPY --chmod=0755 docker-entrypoint.sh /usr/local/bin/docker-entrypoint

EXPOSE 7777

ENTRYPOINT ["/usr/local/bin/docker-entrypoint"]
