FROM alpine:3.20

# Intentionally do NOT install ncurses-dev: omz.sh should build ncurses locally.
RUN apk add --no-cache \
    bash \
    ca-certificates \
    curl \
    git \
    python3 \
    tmux \
    tar \
    xz \
    gzip \
    make \
    gcc \
    musl-dev \
    linux-headers \
    findutils \
    pkgconf \
    autoconf \
    perl \
    shellcheck

RUN adduser -D -s /bin/bash runner
USER runner
WORKDIR /repo

