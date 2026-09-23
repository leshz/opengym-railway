# Track upstream openGym releases on Railway

## Objective
Every Railway deploy builds the latest stable release of `DuarteSantos8/openGym`, so new upstream
features arrive without merging code into this repo.

## Problem / why
The repo vendored openGym v1.2.4 (via `arvids-unavailable/openGym`). The maintained upstream is
`DuarteSantos8/openGym` (v1.3.8, frequent releases) and shares no git history with this repo.

## Scope
- Dockerfile fetches upstream at build time (`UPSTREAM_REF`, default `latest` = newest `vX.Y.Z`).
- Reuse upstream `web/nginx.conf.template`; entrypoint renders it for a same-container backend.
- Remove vendored app code; update README and env reference.
- Deploy to the existing Railway service (target confirmed with the user; never a new project).

## Decisions
- Latest stable release, not `main` (user choice, 2026-09-22).
- Cache busting via remote `ADD .../releases.atom` (byte-stable; avoids REST API rate limit).
- TDD: infra/glue only, no test runner; verification is build + container smoke tests.

## Tasks
- [x] T1 Dockerfile + entrypoint + upstream nginx template (route: inline)
- [x] T2 Remove vendored code; README / env.example / .dockerignore (route: inline)
- [ ] T3 Deploy to Railway production + verify health and version

## Verification evidence
- `docker build` resolved `v1.3.8`; `--build-arg UPSTREAM_REF=v1.3.7` built v1.3.7; rebuild reused cache.
- Container with a copy of v1.2.4 `data/`: log `openGym v1.3.8 starting`, `/api/health` →
  `{"ok":true,"users":1}` (existing account kept), `X-Frame-Options: DENY` + CSP from upstream
  template, bundle points at jsDelivr `@7455efae…`, sample image 200, `coach` user present.

## Next step
Confirm the Railway target (`opengym` project vs `Shztech.dev`), back up `/data`, deploy.
