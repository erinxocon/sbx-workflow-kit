# syntax=docker/dockerfile:1
#
# Overlay that lands on any sbx agent workload (claude, codex, shell, ...):
#   uv, git-lfs            static binaries in /usr/local/bin
#   nvm + Node             /opt/nvm (NVM_DIR), Node pinned by NODE_VERSION
#   global npm tools       @playwright/cli, @bigcommerce/stencil-cli,
#                          installed under that Node and exposed through
#                          wrapper scripts in /usr/local/bin
#   Playwright browsers    NOT here: ../template bakes Chromium and its apt
#                          libraries into /opt/ms-playwright
FROM dhi.io/debian-base:trixie-dev AS build
ARG TARGETARCH
ARG UV_VERSION
ARG GIT_LFS_VERSION
ARG NVM_VERSION
ARG NODE_VERSION
ARG PLAYWRIGHT_CLI_VERSION
ARG STENCIL_CLI_VERSION

# python3/make/g++: Stencil's @bigcommerce/node-sass compiles libsass from
# source when its prebuilt binary cannot be fetched.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl xz-utils bash git \
      python3 make g++ \
 && rm -rf /var/lib/apt/lists/*

# --- uv (static musl build) -------------------------------------------------
RUN set -eux; \
    case "$TARGETARCH" in \
      amd64) t=x86_64-unknown-linux-musl ;; \
      arm64) t=aarch64-unknown-linux-musl ;; \
      *) echo "unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    mkdir -p /out/usr/local/bin; \
    curl -fsSL "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${t}.tar.gz" \
      | tar -xz -C /out/usr/local/bin --strip-components=1 "uv-${t}/uv" "uv-${t}/uvx"; \
    /out/usr/local/bin/uv --version | grep -q "${UV_VERSION}"

# --- git-lfs (static Go binary) ---------------------------------------------
RUN set -eux; \
    curl -fsSL "https://github.com/git-lfs/git-lfs/releases/download/v${GIT_LFS_VERSION}/git-lfs-linux-${TARGETARCH}-v${GIT_LFS_VERSION}.tar.gz" \
      | tar -xz -C /tmp; \
    install -m 0755 "/tmp/git-lfs-${GIT_LFS_VERSION}/git-lfs" /out/usr/local/bin/git-lfs; \
    /out/usr/local/bin/git-lfs version | grep -q "${GIT_LFS_VERSION}"

# --- nvm + Node + global npm tools ------------------------------------------
# NVM_DIR lives outside /home so the overlay never touches the agent's home.
ENV NVM_DIR=/opt/nvm
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
RUN set -eux; \
    mkdir -p "$NVM_DIR"; \
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" | PROFILE=/dev/null bash; \
    . "$NVM_DIR/nvm.sh"; \
    nvm install "${NODE_VERSION}"; \
    nvm alias default "${NODE_VERSION}"; \
    nvm use default >/dev/null; \
    npm install -g --no-fund --no-audit \
      "@playwright/cli@${PLAYWRIGHT_CLI_VERSION}" \
      "@bigcommerce/stencil-cli@${STENCIL_CLI_VERSION}"; \
    node_bin="$(dirname "$(nvm which default)")"; \
    echo "$node_bin" > /tmp/node_bin; \
    npm cache clean --force; \
    mkdir -p /out/opt/ms-playwright /out/usr/local/bin; \
    cp -a "$NVM_DIR" /out/opt/nvm

# Wrapper scripts, not symlinks: the bins' shebang is `#!/usr/bin/env node`,
# which would resolve the *base image's* node (older than stencil's >=24).
# Each wrapper pins this kit's Node first on PATH, then execs the real bin.
RUN set -eux; \
    node_bin="$(cat /tmp/node_bin)"; \
    for bin in stencil playwright-cli; do \
      test -e "${node_bin}/${bin}"; \
      printf '#!/bin/sh\nPLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright PATH="%s:$PATH" exec "%s/%s" "$@"\n' \
        "${node_bin}" "${node_bin}" "${bin}" > "/out/usr/local/bin/${bin}"; \
      chmod 0755 "/out/usr/local/bin/${bin}"; \
    done; \
    for bin in node npm npx; do \
      printf '#!/bin/sh\nPLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright PATH="%s:$PATH" exec "%s/%s" "$@"\n' \
        "${node_bin}" "${node_bin}" "${bin}" > "/out/usr/local/bin/kit-${bin}"; \
      chmod 0755 "/out/usr/local/bin/kit-${bin}"; \
    done; \
    # nvm for interactive/login shells. Core nvm.sh only: never source
    # bash_completion here (it breaks CLAUDE_ENV_FILE-sourced shells).
    mkdir -p /out/etc/profile.d; \
    # nvm refuses to load while NPM_CONFIG_PREFIX is set, and the sandbox
    # templates set it. Login shells drop it so nvm owns the npm prefix.
    printf 'unset NPM_CONFIG_PREFIX\nexport NVM_DIR=/opt/nvm\n[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"\n' \
      > /out/etc/profile.d/workflow-tools-nvm.sh

# Release tarballs and nvm's clone carry foreign uids; hand the tree to
# root, then make the nvm/playwright trees agent-writable so `nvm install`
# and `npm i -g` keep working inside the sandbox.
RUN chown -R 0:0 /out && chown -R 1000:1000 /out/opt/nvm /out/opt/ms-playwright

FROM scratch
COPY --from=build /out /
ENV NVM_DIR=/opt/nvm
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
