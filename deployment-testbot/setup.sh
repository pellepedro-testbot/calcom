#!/usr/bin/env bash
# Build the Cal.com SUT FROM SOURCE and wait until healthy.
# Cal.com facts (verified 2026-07-14):
#   Port: 3000 | Health: GET http://localhost:3000 | Root Dockerfile builds apps/web (Next.js) from source.
#   start.sh (in-image) runs `prisma migrate deploy` + app-store seed before `yarn start`.
#
# The Next.js from-source build is heavy (MAX_OLD_SPACE_SIZE=6144 default) — ~20-35 min cold.
# In GitHub Actions we layer-cache the expensive build stages via a docker-container buildx
# builder + the GHA cache backend (docker-compose.ci.yml). Locally we build plainly (no gha backend).
set -euo pipefail
cd "$(dirname "$0")"

# Base compose always applies. In CI, overlay the GHA build cache and route the build through
# buildx bake (which honors cache_from/cache_to). CI-only because `type=gha` needs the Actions
# cache tokens, absent on a laptop.
COMPOSE=(-f docker-compose.yml)
if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  COMPOSE+=(-f docker-compose.ci.yml)
  export COMPOSE_BAKE=true
  echo "==> CI detected: enabling buildx GHA layer cache (docker-compose.ci.yml)"
fi

echo "==> Building Cal.com SUT from source + starting..."
docker compose "${COMPOSE[@]}" up -d --build

echo "==> Waiting for the web app on :3000 (DB migrate + app-store seed run on first boot)..."
for i in $(seq 1 300); do
  if curl -fsS -m 5 -o /dev/null http://localhost:3000; then
    echo "==> SUT healthy"
    echo "==> Open http://localhost:3000"
    exit 0
  fi
  sleep 5
  if [[ $i -eq 300 ]]; then
    echo "!! SUT failed to become healthy in time — recent logs:"
    docker compose "${COMPOSE[@]}" logs --tail 120 calcom
    exit 1
  fi
done
