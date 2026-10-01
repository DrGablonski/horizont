# ── Stage 1: Build ──────────────────────────────────────────────────────────
FROM oven/bun:1 AS build
WORKDIR /app

# Dependencies first (Docker layer cache)
COPY package.json bun.lock* ./
RUN bun install --frozen-lockfile

# Source + production build
COPY . .
RUN bun run build

# Shrink to production dependencies only
RUN bun install --production --frozen-lockfile

# ── Stage 2: Runtime ────────────────────────────────────────────────────────
FROM node:22-alpine
WORKDIR /app

ENV NODE_ENV=production \
    TZ=Europe/Berlin \
    HOST=0.0.0.0 \
    PORT=3000 \
    DATA_DIR=/app/data

# Production deps + build output
COPY --from=build /app/package.json ./package.json
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/build ./build

# Persistierte Daten (Workflows + CalDAV-Einstellungen)
RUN mkdir -p /app/data
VOLUME /app/data

EXPOSE 3000

CMD ["node", "build/index.js"]
