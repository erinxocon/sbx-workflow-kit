# docker-sandbox-custom-kit

Custom Docker Sandboxes (`sbx`) setup for my workflow, in two parts:

| Part | What | Changes |
|---|---|---|
| [`template/`](template/Dockerfile) | Heavy layer baked into an image: Playwright Chromium + its apt libraries, on top of the v3 workload image (`docker/sbx-kit-claude`, overridable with `--build-arg BASE=...`) | rarely, slow to build |
| [`workflow-tools/`](workflow-tools/README.md) | v3 mixin kit: uv, nvm + Node 24, git-lfs (system-wide), `playwright-cli` + its skill, BigCommerce `stencil`, network rules, agent context | often, cheap |

`docs/upstream/` is a copy of Docker's kit spec and examples
([docker/sandbox-kit-spec](https://github.com/docker/sandbox-kit-spec),
commit `6b0bc25`).

## Try it locally

On the host (the machine running `sbx`, not inside a sandbox):

```console
# 1. build the template
$ docker build -t workflow-claude:dev template/

# 2. sbx's daemon can't see your local images; hand it a tar
$ docker image save workflow-claude:dev -o workflow-claude.tar
$ sbx template load workflow-claude.tar

# 3. run it with the kit layered on top
$ BUILDX_BUILDER=kit-builder sbx run --pull never -t workflow-claude:dev claude --kit ./workflow-tools --name wf .

# later: re-attach without rebuilding (no --kit)
$ sbx run --name wf
```

Local kit builds need a builder that can export OCI. Create it once with
`docker buildx create --name kit-builder --driver docker-container --bootstrap`.

Rebuild the template only when the Playwright CLI version (or the base image)
changes; edit `workflow-tools/` freely without touching it. Keep
`PLAYWRIGHT_CLI_VERSION` in `template/Dockerfile` equal to the kit's
`playwrightCliVersion` arg, since the browser revision follows the CLI version.

## Later: Docker Hub

```console
$ docker tag workflow-claude:dev <hub-user>/workflow-claude:0.1.0
$ docker push <hub-user>/workflow-claude:0.1.0
$ sbx run --template docker.io/<hub-user>/workflow-claude:0.1.0 claude --kit ./workflow-tools
```

`sbx` does not add `docker.io/` for you. For a private repo `sbx login` is
enough on Docker Hub.

## Status

- Kit only: built and run through `sbx` v3 workload on macOS; tools, LFS config
  and skill files confirmed.
- Template + kit: exercised with plain `docker` on the Ubuntu workload image
  (Chromium launch, node-sass). **Not yet run through `sbx`.**
- Not confirmed: Claude listing the skill in `/skills`; whether the kit's network
  policy is what allows its hosts.
