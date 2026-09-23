# openGym — single-container image for Railway, built from the latest upstream release.
#
# This repository holds only the Railway glue. The application source is fetched from
# github.com/DuarteSantos8/openGym at build time, so every deploy picks up the newest
# release without touching this repo. Set the UPSTREAM_REF service variable (e.g. v1.3.7)
# to pin a version or roll back; leave it unset (or "latest") to follow releases.
#
# Railway deploys individual services, not docker-compose. Upstream splits into `web`
# (nginx) + `api` (node) + a one-shot `media` downloader. Passkeys (WebAuthn) require the
# app and its API to share ONE origin, so both run here in a single container: nginx serves
# the SPA on Railway's $PORT and proxies /api to node on 127.0.0.1:3000.

# --- Upstream source ---------------------------------------------------------------------
FROM alpine:3 AS source
RUN apk add --no-cache git
ARG UPSTREAM_REPO=DuarteSantos8/openGym
ARG UPSTREAM_REF=latest
# Cache-buster: a remote ADD is re-checked on every build, so this layer (and everything
# after it) is invalidated exactly when a new release is published. The Atom feed is used
# instead of the REST API to stay clear of its 60 req/h limit on shared build machines.
ADD https://github.com/${UPSTREAM_REPO}/releases.atom /tmp/releases.atom
RUN set -eu; \
    ref="${UPSTREAM_REF}"; \
    if [ -z "$ref" ] || [ "$ref" = "latest" ]; then \
      ref="$(git ls-remote --tags --sort=-v:refname "https://github.com/${UPSTREAM_REPO}.git" \
        | awk '{print $2}' | grep -v '\^{}$' | sed 's#^refs/tags/##' \
        | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1)"; \
    fi; \
    [ -n "$ref" ] || { echo "FATAL: could not resolve an upstream release tag" >&2; exit 1; }; \
    echo "Building openGym ${ref} from ${UPSTREAM_REPO}"; \
    git clone --depth 1 --branch "$ref" "https://github.com/${UPSTREAM_REPO}.git" /src; \
    echo "$ref" > /src/.upstream-ref; \
    # Exercise media comes from a CDN, pinned to the dataset commit upstream's own mobile
    # build uses — read from its package.json so it follows upstream too.
    sha="$(grep -oE 'exercises-dataset@[0-9a-f]{40}' /src/frontend/package.json | head -n 1 | cut -d@ -f2 || true)"; \
    echo "${sha:-7455efae41b330c265e7cd4b78dfa848e7ce5ebd}" > /src/.media-sha

# --- Frontend (mirrors upstream web/Dockerfile) -------------------------------------------
# --platform=$BUILDPLATFORM: Vite output is arch-independent, and QEMU-emulated npm installs
# are known to corrupt esbuild/rollup's native binaries (upstream documents this).
FROM --platform=$BUILDPLATFORM node:22-alpine AS build
# The frontend imports api/coach/core via ../../../api/coach/core, so both keep their
# relative position from the upstream repository.
WORKDIR /app/frontend
COPY --from=source /src/frontend/package.json /src/frontend/package-lock.json* ./
# --ignore-scripts: skips @capacitor/assets -> sharp (app-icon tooling, not needed here).
RUN npm ci --ignore-scripts
COPY --from=source /src/api/coach/core/ /app/api/coach/core/
COPY --from=source /src/frontend/ ./
COPY --from=source /src/.media-sha /tmp/.media-sha
RUN sha="$(cat /tmp/.media-sha)" \
 && VITE_IMG_BASE="https://cdn.jsdelivr.net/gh/hasaneyldrm/exercises-dataset@${sha}/images/" \
    VITE_GIF_BASE="https://cdn.jsdelivr.net/gh/hasaneyldrm/exercises-dataset@${sha}/videos/" \
    npm run build

# --- API dependencies (mirrors upstream api/Dockerfile, default target) -------------------
FROM node:22-alpine AS api
WORKDIR /app/api
COPY --from=source /src/api/ ./
# --omit=optional: no AI runtime (Agent SDK / Codex), same as upstream's default image.
RUN npm ci --omit=dev --omit=optional && npm cache clean --force && rm -rf test

# --- Runtime -----------------------------------------------------------------------------
FROM node:22-alpine
# gettext provides envsubst, used to render upstream's nginx template at start-up.
RUN apk upgrade --no-cache && apk add --no-cache nginx gettext
# Coach jobs drop to this user and fail closed if it does not exist (upstream api/Dockerfile).
RUN adduser -D -H -s /sbin/nologin coach

COPY --from=build /app/frontend/dist /usr/share/nginx/html
COPY --from=api /app/api /app/api
COPY --from=source /src/web/nginx.conf.template /etc/nginx/nginx.conf.template
COPY --from=source /src/.upstream-ref /.upstream-ref

COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

ENV NODE_ENV=production \
    DATA_DIR=/data \
    PORT=8080

# /data holds accounts, passkeys, the session secret and VAPID keys. Railway manages the
# volume itself and REJECTS a Dockerfile VOLUME instruction, so the mount is declared in the
# service config (mount path /data) rather than here.
EXPOSE 8080

ENTRYPOINT ["/docker-entrypoint.sh"]
