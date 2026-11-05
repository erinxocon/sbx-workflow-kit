# workflow-tools

A Docker Sandboxes v3 **mixin** kit. It overlays onto any agent workload
(claude, codex, shell, ...). It does not replace the base image.

| Tool | Where | Notes |
|---|---|---|
| `uv`, `uvx` | `/usr/local/bin` | static musl build |
| `git-lfs` | `/usr/local/bin` | `git lfs install --system` runs in an install hook (writes `/etc/gitconfig`) |
| `nvm` + Node 24 | `/opt/nvm` | sourced by `/etc/profile.d/workflow-tools-nvm.sh` (login shells) |
| `playwright-cli` | `/usr/local/bin` wrapper | not baked in: install hooks run `install-browser --with-deps` (root, into `/opt/ms-playwright`) and `install --skills -g` (agent) at sandbox creation |
| `stencil` (BigCommerce) | `/usr/local/bin` wrapper | needs Node >= 24 |
| `kit-node`, `kit-npm`, `kit-npx` | `/usr/local/bin` | always this kit's Node |

The `stencil`, `playwright-cli` and `kit-*` wrappers pin this kit's Node first
on `PATH`, so they work whatever `node` the base image ships.

Versions are `args` in `workflow-tools.yaml`; override with `--kit-arg`.

## Use

```console
# local directory, built when the sandbox is created
$ sbx run claude --kit ./workflow-tools

# or build and publish
$ docker buildx build -f workflow-tools.yaml -t <registry>/workflow-tools:0.1.0 --push .
$ sbx run claude --kit <registry>/workflow-tools:0.1.0
```

Kits attach at sandbox creation; to change one, create a new sandbox.

## Notes

- Stencil's `@bigcommerce/node-sass` compiles from source at build time (the
  prebuilt binary download is unreliable), so the build stage needs
  python3/make/g++. These never reach the overlay.
- Browsers download at every sandbox creation (~hundreds of MB plus apt
  libraries), so creation is slower than with a baked-in browser.
- A full local build uses about 9 GB of BuildKit cache. The Docker volume in
  the sandbox is 9.8 GB, so run `docker builder prune -af` between builds.
- Login shells run `unset NPM_CONFIG_PREFIX` because nvm refuses to load while
  the sandbox templates' prefix is set. `npm i -g` in a login shell then
  installs into nvm's Node.
- Install-phase network is open only for apt and the Playwright browser CDN. Runtime
  network allows GitHub (+ LFS hosts), PyPI, npm, nodejs.org, and BigCommerce.
