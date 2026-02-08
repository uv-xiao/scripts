FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

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
    libncurses5-dev \
    libncursesw5-dev \
    yodl \
    shellcheck \
  && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash runner
USER runner
WORKDIR /repo
