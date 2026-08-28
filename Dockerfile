# openGym — single-container image for Railway.
#
# Railway deploys individual services, not docker-compose. The upstream project splits
# into `web` (nginx) + `api` (node) + a one-shot `media` downloader. Passkeys (WebAuthn)
# require the app and its API to share ONE origin, so both run here in a single container:
# nginx serves the SPA on Railway's $PORT and proxies /api to node on 127.0.0.1:3000.
#
# Exercise media (~140 MB) is served from a CDN rather than baked in — the same approach
# the upstream `build:mobile` script already uses.

# --platform=$BUILDPLATFORM pins the build stage to the host's native arch even when
# cross-building. Vite output is arch-independent, and QEMU-emulated npm installs are known
# to corrupt esbuild/rollup's native binaries (upstream documents this).
FROM --platform=$BUILDPLATFORM node:22-alpine AS build
WORKDIR /app

# Exercise images/GIFs, pinned to the dataset commit the upstream mobile build uses.
# Pinned (not @latest) so a template deployed today builds identically in six months.
ARG MEDIA_SHA=7455efae41b330c265e7cd4b78dfa848e7ce5ebd
ENV VITE_IMG_BASE=https://cdn.jsdelivr.net/gh/hasaneyldrm/exercises-dataset@${MEDIA_SHA}/images/
ENV VITE_GIF_BASE=https://cdn.jsdelivr.net/gh/hasaneyldrm/exercises-dataset@${MEDIA_SHA}/videos/

COPY frontend/package.json frontend/package-lock.json* ./
RUN npm ci 2>/dev/null || npm install
COPY frontend/ ./
RUN npm run build

# Production API dependencies, resolved separately so they stay out of the final layer graph.
FROM node:22-alpine AS api-deps
WORKDIR /app/api
COPY api/package.json api/package-lock.json* ./
RUN npm install --omit=dev && npm cache clean --force

FROM node:22-alpine
# gettext provides envsubst, used to inject Railway's $PORT into the nginx config.
RUN apk add --no-cache nginx gettext

COPY --from=build /app/dist /usr/share/nginx/html
COPY --from=api-deps /app/api/node_modules /app/api/node_modules
COPY api/package.json api/server.js /app/api/

COPY nginx.railway.conf.template /etc/nginx/nginx.conf.template
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
