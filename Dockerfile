# Horizont – zwei Build-Ziele aus einem Branch:
#
#   docker build --target web      →  Web-App + API   (Standard)
#   docker build --target headless →  nur API (ohne Web-UI)
#
# In docker-compose: docker-compose.yml (web) bzw. docker-compose.headless.yml.

# ── Stage 1: Build (Abhängigkeiten, gemeinsam gecacht) ─────────────────────
FROM oven/bun:1 AS build
WORKDIR /app

# Dependencies first (Docker layer cache)
COPY package.json bun.lock* ./
RUN bun install --frozen-lockfile

COPY . .

# ── Stage 2a: Web-Build (alles wie im Repo) ────────────────────────────────
FROM build AS build-web
RUN bun run build
RUN bun install --production --frozen-lockfile

# ── Stage 2b: Headless-Build (Seiten/Components/Assets vor dem Build raus) ─
# behält: src/server/**, src/routes/api/**, hooks, lib/{types,categories,dates}
FROM build AS build-headless
RUN rm -rf src/app.css src/lib/components src/lib/api.ts src/lib/theme.ts \
        src/lib/utils.ts src/routes/+page.svelte src/routes/+layout.svelte \
        src/routes/+layout.ts src/routes/archiv src/routes/einstellungen \
        src/routes/fokus src/routes/login src/routes/setup static components.json \
        apple .claude && \
    bun run build && \
    bun install --production --frozen-lockfile

# ── Stage 3: Runtime Web ────────────────────────────────────────────────────
FROM node:22-alpine AS web
WORKDIR /app

ENV NODE_ENV=production \
    TZ=Europe/Berlin \
    HOST=0.0.0.0 \
    PORT=3000 \
    DATA_DIR=/app/data

COPY --from=build-web /app/package.json ./package.json
COPY --from=build-web /app/node_modules ./node_modules
COPY --from=build-web /app/build ./build

# Persistierte Daten (Workflows + CalDAV-Einstellungen)
RUN mkdir -p /app/data
VOLUME /app/data

EXPOSE 3000

CMD ["node", "build/index.js"]

# ── Stage 4: Runtime Headless (nur API, schlankeres Image) ─────────────────
FROM node:22-alpine AS headless
WORKDIR /app

ENV NODE_ENV=production \
    TZ=Europe/Berlin \
    HOST=0.0.0.0 \
    PORT=3000 \
    DATA_DIR=/app/data

COPY --from=build-headless /app/package.json ./package.json
COPY --from=build-headless /app/node_modules ./node_modules
COPY --from=build-headless /app/build ./build

RUN mkdir -p /app/data
VOLUME /app/data

EXPOSE 3000

CMD ["node", "build/index.js"]
