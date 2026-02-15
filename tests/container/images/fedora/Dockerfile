FROM fedora:41

# Intentionally do NOT install ncurses-devel: omz.sh should build ncurses locally.
RUN dnf install -y \
    bash \
    ca-certificates \
    curl \
    findutils \
    git \
    make \
    gcc \
    glibc-devel \
    python3 \
    tar \
    xz \
    gzip \
    tmux \
    pkgconf-pkg-config \
    autoconf \
    ShellCheck \
  && dnf clean all

RUN useradd -m -s /bin/bash runner
USER runner
WORKDIR /repo

