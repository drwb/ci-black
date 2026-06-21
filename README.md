# ci-black

Reusable GitHub Actions CI/CD for **drwb's Docker home-lab apps** (the home network —
`ghcr.io/drwb/*` images running on the docker hosts). `ci-<env>` naming leaves room for sibling
repos (e.g. a future `ci-<other-env>`) if other environments ever need their own pipeline.

**Out of scope:** Cloudflare Workers projects (`<worker-template>*`, `<worker-app>`) — those deploy via
`wrangler` on cloud runners and have no firewall problem.

## The pattern

```
push to main (drwb/<app>)
  └─ caller `uses: drwb/ci-black/.github/workflows/build.yml@v1`
       ├─ test   (PR + push)            uv sync --frozen → [lint] → test_command
       └─ build  (needs: test, main)    push ghcr  :latest + :sha     ← only ever runs green
                                                    │
   <docker-host> watchtower ── pulls :latest on digest change ──▶ recreate <app>
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

Multi-image example (<app-d>):

```yaml
    with:
      images: >-
        [{"name":"<app-d>","dockerfile":"Dockerfile","context":"."},
         {"name":"<app-d>-tor","dockerfile":"deploy/Dockerfile.tor","context":"."}]
      test_command: 'uv run pytest -q -m "not integration"'
```

## Near-immediate delivery (LAN side)

A dedicated `watchtower-ci` instance on <docker-host> (`WATCHTOWER_SCOPE=ci`, short interval) watches only
containers labelled `com.centurylinklabs.watchtower.scope=ci`; the main <docker-host> watchtower runs
`WATCHTOWER_SCOPE=none` so it manages everything else on the lab's normal 03:00 cadence. Add the
`scope=ci` label to a stack's compose to opt it into fast delivery. See the stacks repo and the
runbook.

## Rollback

`:latest` follows the newest green build. To roll back, re-tag a previous `:sha` as `:latest` in ghcr;
watchtower restores it on the next pass.

## Notes

- `drwb` is a GitHub **User** (not an org). Cross-repo reuse requires this repo's
  Settings → Actions → "Access" = *Accessible from repositories owned by the user drwb*.
- Actions are pinned to major-version tags to match the rest of the lab; SHA-pinning is a possible
  future hardening for this shared trust root.
- `main` is protected (see `.claude/settings.json` + `scripts/hooks/`). Change via PR.
