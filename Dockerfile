# syntax=docker/dockerfile:1

# Debian (glibc) base — matches the platform the lockfile is generated on and
# avoids Alpine/musl cross-platform optional-dependency mismatches with
# native build tools like lightningcss (Tailwind v4).

# ---- Dependencies ----
FROM node:22-slim AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

# ---- Build ----
FROM node:22-slim AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
# mongo.ts connects lazily, so no MONGODB_URI is needed at build time.
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build

# ---- Runtime ----
FROM node:22-slim AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=3000
ENV HOSTNAME=0.0.0.0

# Build-time metadata, injected by CI (docker/metadata-action) or `docker build --build-arg`.
ARG VERSION=dev
ARG REVISION
ARG CREATED

# OCI image labels — surfaced as title/description/source/license on Docker Hub and GHCR.
LABEL org.opencontainers.image.title="Mongui" \
  org.opencontainers.image.description="A lightweight, self-hosted web UI for browsing and editing MongoDB — a maintained replacement for the deprecated mongo-express." \
  org.opencontainers.image.url="https://github.com/Soumya7681/monogui" \
  org.opencontainers.image.source="https://github.com/Soumya7681/monogui" \
  org.opencontainers.image.documentation="https://github.com/Soumya7681/monogui#readme" \
  org.opencontainers.image.licenses="MIT" \
  org.opencontainers.image.authors="Soumyaranjan" \
  org.opencontainers.image.vendor="Soumyaranjan" \
  org.opencontainers.image.version="${VERSION}" \
  org.opencontainers.image.revision="${REVISION}" \
  org.opencontainers.image.created="${CREATED}"

# Run as a non-root user.
RUN groupadd --system --gid 1001 nodejs \
  && useradd --system --uid 1001 --gid nodejs nextjs

# Standalone output bundles only what the server needs.
COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs
EXPOSE 3000

# The standalone build emits server.js at the project root.
CMD ["node", "server.js"]
