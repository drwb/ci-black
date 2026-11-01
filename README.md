# ci-black

Reusable GitHub Actions CI/CD for drwb's self-hosted Docker apps (`ghcr.io/drwb/*` images pulled by a
watchtower-managed host). `ci-<env>` naming leaves room for sibling repos if another environment ever
needs its own pipeline.

**Out of scope:** Cloudflare Workers projects, which deploy via `wrangler` on cloud runners.

## The pattern

```
push to main (drwb/<app>)
  └─ caller `uses: drwb/ci-black/.github/workflows/build.yml@v1`
       ├─ test   (PR + push)            uv sync --frozen → [lint] → test_command
       └─ build  (needs: test, main)    push ghcr  :latest + :sha     ← only ever runs green
                                                    │
   docker-host watchtower ── pulls :latest on digest change ──▶ recreate <app>
```

**Why there's no deploy job.** "Deploy only if tests pass" is enforced at *publish* time: `build`
has `needs: test` and only runs on a green main push, so `ghcr.io/drwb/<app>:latest` is — by
definition — test-passed. A red test skips `build`, so `:latest` never moves. The existing,
pull-based watchtower deploys `:latest`, which is therefore inherently gated. No self-hosted runner,
no PAT, no inbound firewall hole.

Trade-off: deploy is *near-immediate* (watchtower poll cadence), not instant.

## Using it

Add one file to a project, `.github/workflows/ci.yml`:

```yaml
name: ci-cd
on:
  push: { branches: [main] }
  pull_request:
permissions:
  contents: read
  packages: write
jobs:
  pipeline:
    uses: drwb/ci-black/.github/workflows/build.yml@v1
    with:
      image: <name>                 # -> ghcr.io/drwb/<name>
      test_command: "uv run pytest -q"
      # lint_command: "uv run ruff check ."   # optional
    secrets: inherit
```

Then delete the project's old `docker.yml` / standalone `pytest.yml`.

### Inputs

| Input | Default | Notes |
|---|---|---|
| `image` | — | single-image short name → `ghcr.io/drwb/<image>` |
| `images` | — | JSON array `[{name,dockerfile,context}]` for multi-image repos (overrides `image`) |
| `test_command` | `uv run pytest -q` | runs after `uv sync --frozen` |
| `lint_command` | `''` | optional; skipped when empty |
| `dockerfile` / `context` | `Dockerfile` / `.` | single-image build inputs |
| `platforms` | `linux/amd64` | build platforms |
| `cache_paths` | `''` | optional extra paths cached in the `test` job (one per line), e.g. `~/.cache/ms-playwright` for browser tests |
| `cache_key_files` | `uv.lock` | glob(s) whose hash keys that cache |
| `extra_branches` | `''` | optional comma-separated branches (no spaces) that also publish on push, tagged `:<branch>` (never `:latest`); e.g. `dev` for a dev environment. The caller's `on.push.branches` must list them too |

The build also passes `GIT_SHA=<commit>` as a Docker build argument. A Dockerfile that declares `ARG GIT_SHA` can bake it in (e.g. `ENV APP_BUILD=$GIT_SHA`) and report it from a health endpoint, so a post-deploy check can wait for exactly that build instead of guessing. Dockerfiles that don't declare it just get a BuildKit warning.

Multi-image example:

```yaml
    with:
      images: >-
        [{"name":"myapp","dockerfile":"Dockerfile","context":"."},
         {"name":"myapp-tor","dockerfile":"deploy/Dockerfile.tor","context":"."}]
      test_command: 'uv run pytest -q -m "not integration"'
```

## Near-immediate delivery (LAN side)

A dedicated `watchtower-ci` instance on the docker host (`WATCHTOWER_SCOPE=ci`, short interval) watches only
containers labelled `com.centurylinklabs.watchtower.scope=ci`; the main watchtower on that host runs
`WATCHTOWER_SCOPE=none` so it manages everything else on its normal nightly cadence. Add the `scope=ci` label to a
stack's compose to opt it into fast delivery.

## Rollback

`:latest` follows the newest green build. To roll back, re-tag a previous `:sha` as `:latest` in ghcr;
watchtower restores it on the next pass.

## Notes

- `drwb` is a GitHub **User** (not an org). Cross-repo reuse requires this repo's
  Settings → Actions → "Access" = *Accessible from repositories owned by the user drwb*.
- Runners are pinned to a specific image version, not `-latest`: a new `latest` image can run ahead of
  tools that install OS packages (e.g. `playwright install --with-deps`). Bump deliberately.
- Every action is pinned to a commit SHA (the version is in the comment next to it): this workflow is
  a shared trust root for every caller.
- `main` is protected by the pre-push hook in `scripts/hooks/` (`bash scripts/hooks/install.sh` once). Change via PR.
