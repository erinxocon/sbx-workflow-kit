# syntax=docker/dockerfile:1
#
# Heavy, slow-changing layer for the Claude sandbox: Playwright's Chromium and
# the system libraries it needs. Built once; every sandbox created from it
# starts with nothing to download. Everything else (uv, nvm, git-lfs, Stencil,
# network rules, agent context) comes from ../workflow-tools at `--kit` time.
#
# BASE is the published v3 workload for your agent (Ubuntu 26.04 at the time of
# writing, not the Debian dhi.io/sbx-templates images). The steps below do not
# depend on the agent: `docker build --build-arg BASE=<other workload> ...`.
ARG BASE=docker.io/docker/sbx-kit-claude:2.1.267
FROM ${BASE}

# Must match the kit's `playwrightCliVersion` arg: the browser revision
# installed here is the one that @playwright/cli version expects.
ARG PLAYWRIGHT_CLI_VERSION=0.1.23

ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright

USER root
# npx fetches the CLI for this one command and leaves nothing behind; the kit
# provides the long-lived `playwright-cli` wrapper. --with-deps runs apt for
# Chromium's shared libraries (they cannot ride a kit overlay).
RUN set -eux; \
    mkdir -p "$PLAYWRIGHT_BROWSERS_PATH"; \
    npx --yes "@playwright/cli@${PLAYWRIGHT_CLI_VERSION}" install-browser --with-deps chromium; \
    chown -R 1000:1000 "$PLAYWRIGHT_BROWSERS_PATH"; \
    rm -rf /var/lib/apt/lists/* /root/.npm /root/.cache/ms-playwright
USER agent
