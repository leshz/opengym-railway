# openGym on Railway

One-click deploy of [openGym](https://github.com/DuarteSantos8/openGym) — a self-hosted
gym & body-weight tracker with passkey sign-in and no telemetry.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/template/TEMPLATE_ID_PLACEHOLDER)

This repository contains **only the Railway glue**. The application source is downloaded from
the **latest upstream release** at build time, so every deploy ships the newest openGym version.

This repository packages openGym as a **single Railway service**. Upstream ships a three-container
`docker-compose` setup; Railway deploys services individually, so this image runs nginx and the API
together behind one origin — which passkeys require.

---

## ⚠️ Read this before you deploy

**1. Attach the volume.** The template mounts one at `/data`. It holds your accounts, passkeys,
workout history, the session-signing secret and the push keys. **Without it, every redeploy wipes
your account and you cannot log back in.**

**2. Pick your domain first.** Passkeys are cryptographically bound to the hostname they were
created on. Changing `RP_ID` afterwards **invalidates every existing passkey** and locks users out.
If you plan to use a custom domain, set it up *before* anyone registers.

---

## Deploying

Click the button above. The template sets everything up:

| Variable | Value | Why |
|---|---|---|
| `RP_ID` | `${{RAILWAY_PUBLIC_DOMAIN}}` | Hostname the passkey is bound to |
| `ORIGIN` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` | Full origin; enables `Secure` cookies |
| `RP_NAME` | `openGym` | Name shown in the browser's passkey prompt |
| `DATA_DIR` | `/data` | Volume mount path |

No secrets to generate: the session secret and VAPID push keys are created on first boot and stored
on the volume.

Optional settings — see [`env.example.txt`](env.example.txt) for all of them:

| Variable | Default | Effect |
|---|---|---|
| `INVITE_ONLY` | `0` | Set to `1` to require an invite code for new profiles |
| `ADMIN_UIDS` | *(empty)* | Comma-separated user ids that get the admin dashboard |
| `SESSION_DAYS` | `90` | How long a session stays signed in |

To become admin: register your passkey, find your id in `/data/db.json` under `users[].id`, then set
`ADMIN_UIDS` to it.

### Custom domain

Add it in Railway **before anyone registers**, then set `RP_ID` to the bare hostname and `ORIGIN` to
`https://<that hostname>`. Existing passkeys will not survive this change.

---

## How this differs from upstream

| | Upstream (`docker compose`) | This repo (Railway) |
|---|---|---|
| Services | `web` + `api` + `media` | one container: nginx + API |
| API routing | `proxy_pass http://api:3000` | `proxy_pass http://127.0.0.1:3000` |
| Listen port | fixed `8080` | Railway's `$PORT`, injected at boot |
| Exercise media | ~140 MB downloaded into a volume | served from jsDelivr CDN, pinned to a commit |
| App source | the checked-out repo | cloned from the latest upstream release at build time |
| Data | `./data` bind mount | Railway volume at `/data` |

No application code lives here. The `Dockerfile` clones the upstream release and builds it the
same way upstream's `web/Dockerfile` and `api/Dockerfile` do; nginx uses upstream's own
`web/nginx.conf.template`, rendered by `docker-entrypoint.sh` with a same-container backend.

### Why one container

WebAuthn requires the page and its API to share a single origin. Splitting them into two Railway
services would mean either exposing the API publicly on a second domain (which breaks the passkey
binding) or proxying between them anyway. One container is simpler and has fewer failure modes.

### Why the CDN

The exercise images and GIFs are ~140 MB. Baking them in would quadruple the image and slow every
build, for assets that never change. The bundle points at jsDelivr, pinned to the dataset commit
upstream's own `build:mobile` script uses (read from its `package.json` at build time). If jsDelivr is
unreachable the app still works; only the exercise illustrations are missing.

---

## Not using Railway?

Use the upstream project directly — it ships a `docker-compose.yml` and prebuilt images:
<https://github.com/DuarteSantos8/openGym>

---

## Running locally

```bash
docker build -t opengym .
docker run --rm -p 8080:8080 \
  -e PORT=8080 \
  -e RP_ID=localhost \
  -e ORIGIN=http://localhost:8080 \
  -v opengym-data:/data \
  opengym
```

Open <http://localhost:8080>. Passkeys work on `http://localhost` without HTTPS — it is the one
exception browsers make.

```bash
curl localhost:8080/api/health     # {"ok":true,"users":0}
```

---

## Backups

Everything lives on the volume. With the [Railway CLI](https://docs.railway.com/cli/installation):

```bash
railway ssh --service opengym                    # then: tar czf - /data > backup.tar.gz
```

Individual users can also export their own data as JSON from Settings.

---

## Updating openGym

Nothing to merge. Each build resolves the newest stable release tag (`vX.Y.Z`) of
`DuarteSantos8/openGym` and builds it. To pick up a new release, **redeploy the service** in
Railway (or push any commit here). The deploy log prints the version it built, and the container
logs `openGym vX.Y.Z starting` at boot.

A new upstream release does **not** trigger a deploy on its own — it is picked up on the next one.

**Pin or roll back** by setting the `UPSTREAM_REF` service variable to a tag (e.g. `v1.3.7`) and
redeploying. Remove it (or set `latest`) to follow releases again.

Take a volume backup before jumping several versions: upstream migrates `/data` forward, not back.

If a release changes the build layout (renamed paths, new nginx template variables), the build or
boot fails loudly and Railway keeps the previous deployment running. Pin `UPSTREAM_REF` to the last
good tag and adjust `Dockerfile` / `docker-entrypoint.sh`.

---

## Operations notes

- **Single replica by design.** State is JSON files on a volume; concurrent replicas would corrupt
  `db.json`. `railway.json` pins `numReplicas: 1` — don't raise it.
- **Healthcheck** is `/api/health`, which exercises the nginx→API proxy path, not just nginx.
- **The container exits if either process dies**, so Railway restarts it instead of serving a
  frontend that returns 502s on every login attempt.
- `railway.json` (config-as-code) is deprecated by Railway on **2026-12-01**. Every setting in it is
  also expressible in the template UI, so migration is straightforward when required.

---

## Credits & licence

openGym is built by [Duarte Santos](https://github.com/DuarteSantos8/openGym) and licensed under
**AGPL-3.0** — see [LICENSE](LICENSE). This repository only packages the unmodified upstream
release for Railway. Because AGPL covers network use, anyone you host this for is entitled to the
source: the exact release is the tag printed at boot, plus this repository.

Exercise media: [hasaneyldrm/exercises-dataset](https://github.com/hasaneyldrm/exercises-dataset) (CC).
