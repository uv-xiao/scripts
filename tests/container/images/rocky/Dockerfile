FROM rockylinux:9

# Intentionally do NOT install ncurses-devel: omz.sh should build ncurses locally.
RUN dnf -y install \
    bash \
    ca-certificates \
    curl-minimal \
    findutils \
    diffutils \
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
  && dnf clean all

RUN useradd -m -s /bin/bash runner
USER runner
WORKDIR /repo
