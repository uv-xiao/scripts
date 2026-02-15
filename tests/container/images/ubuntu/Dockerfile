FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# Intentionally do NOT install libncurses*-dev here: omz.sh should be able to
# self-satisfy curses/ncurses headers/libs without root by building ncurses.
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    python3 \
    tmux \
    xz-utils \
    gzip \
    tar \
    make \
    gcc \
    libc6-dev \
    pkg-config \
    autoconf \
    yodl \
    shellcheck \
  && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash runner
USER runner
WORKDIR /repo

