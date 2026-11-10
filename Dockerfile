# syntax=docker/dockerfile:1
FROM ubuntu:24.04

ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000
ARG INSTALL_NODE=true
ARG INSTALL_PYTHON=true
ARG INSTALL_PHP=false
ARG INSTALL_RUST=false
ARG INSTALL_GO=false
ARG INSTALL_DOCKER_CLI=true
ARG NODE_MAJOR=22
ARG GO_VERSION=1.24.4

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Base tools that Claude Code and most projects lean on.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget gnupg git git-lfs openssh-client less nano vim \
      ripgrep fd-find jq unzip zip xz-utils procps iproute2 dnsutils \
      build-essential pkg-config libssl-dev sudo tzdata \
 && ln -s /usr/bin/fdfind /usr/local/bin/fd \
 && rm -rf /var/lib/apt/lists/*

# Node.js (+ corepack for pnpm / yarn)
RUN if [ "$INSTALL_NODE" = "true" ]; then \
      curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash - \
   && apt-get install -y --no-install-recommends nodejs \
   && corepack enable \
   && rm -rf /var/lib/apt/lists/*; \
    fi

# Python
RUN if [ "$INSTALL_PYTHON" = "true" ]; then \
      apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-venv python3-pip python3-dev pipx \
   && rm -rf /var/lib/apt/lists/*; \
    fi

# PHP + Composer
RUN if [ "$INSTALL_PHP" = "true" ]; then \
      apt-get update && apt-get install -y --no-install-recommends \
        php-cli php-mbstring php-xml php-curl php-sqlite3 php-mysql php-pgsql \
        php-redis php-zip php-intl php-bcmath php-gd \
   && curl -fsSL https://getcomposer.org/installer \
        | php -- --install-dir=/usr/local/bin --filename=composer \
   && rm -rf /var/lib/apt/lists/*; \
    fi

# Go
RUN if [ "$INSTALL_GO" = "true" ]; then \
      arch="$(dpkg --print-architecture)" \
   && curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${arch}.tar.gz" | tar -C /usr/local -xz; \
    fi
ENV PATH="/usr/local/go/bin:${PATH}"

# Docker CLI + Compose plugin (talks to the host daemon via compose.docker.yml)
RUN if [ "$INSTALL_DOCKER_CLI" = "true" ]; then \
      install -m 0755 -d /etc/apt/keyrings \
   && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
   && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        > /etc/apt/sources.list.d/docker.list \
   && apt-get update && apt-get install -y --no-install-recommends docker-ce-cli docker-compose-plugin \
   && rm -rf /var/lib/apt/lists/*; \
    fi

# GitHub CLI; also serves as git's credential helper for github.com (uses GH_TOKEN)
RUN install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/* \
 && git config --system credential.https://github.com.helper '' \
 && git config --system --add credential.https://github.com.helper '!/usr/bin/gh auth git-credential'

# Non-root user matching your host UID/GID so files you create are yours.
# Ubuntu 24.04 ships a default "ubuntu" user on 1000:1000; remove it first.
RUN if id ubuntu >/dev/null 2>&1; then userdel -r ubuntu; fi \
 && if ! getent group "$USER_GID" >/dev/null; then groupadd --gid "$USER_GID" "$USERNAME"; fi \
 && useradd --uid "$USER_UID" --gid "$USER_GID" --create-home --shell /bin/bash "$USERNAME" \
 && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME" \
 && chmod 0440 "/etc/sudoers.d/$USERNAME"

USER $USERNAME
WORKDIR /home/$USERNAME

# Pre-create volume mount points so named volumes inherit this user's ownership.
RUN mkdir -p .claude-devbox .cache .npm .cargo/registry .local/bin

# Rust (per-user)
RUN if [ "$INSTALL_RUST" = "true" ]; then \
      curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal --component clippy,rustfmt; \
    fi

# Claude Code (native installer)
RUN curl -fsSL https://claude.ai/install.sh | bash

ENV PATH="/home/${USERNAME}/.local/bin:/home/${USERNAME}/.cargo/bin:${PATH}"

CMD ["sleep", "infinity"]
