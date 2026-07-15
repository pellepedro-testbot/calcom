#!/usr/bin/env bash
# Build the Cal.com SUT FROM SOURCE, wait until healthy, and seed a login user.
# Cal.com facts (verified 2026-07-14/15):
#   Port: 3000 | Health: GET http://localhost:3000 | Root Dockerfile builds apps/web (Next.js) from source.
#   start.sh (in-image) runs `prisma migrate deploy` + app-store seed before `yarn start`.
#   Auth: NextAuth. `POST /api/auth/signup` creates a user (password hashed into UserPassword);
#         the account can log in immediately (no email verification required) — verified live.
#
# The Next.js from-source build is heavy (MAX_OLD_SPACE_SIZE=6144 default) — ~20-35 min cold.
set -euo pipefail
cd "$(dirname "$0")"

# NOTE: gha buildx cache intentionally disabled for cal.com. Its ~7.3GB image exceeds GitHub
# Actions' ~10GB cache quota with mode=max, and `issue_comment`-triggered runs get a read-only
# token (cache writes denied) — both cause "failed to reserve cache" build failures. Plain
# from-source build is slower (~20min) but reliable.
COMPOSE=(-f docker-compose.yml)

# SUT base URL — override locally when :3000 is taken, e.g. SUT_BASE_URL=http://localhost:3001
SUT_BASE_URL="${SUT_BASE_URL:-http://localhost:3000}"

# Login user to seed so authed tests (and testbot's auth token) have a real session.
SEED_EMAIL="${SEED_EMAIL:-testbot@dev.local}"
SEED_PASSWORD="${SEED_PASSWORD:-Testb0t-Pass123!}"
SEED_USERNAME="${SEED_USERNAME:-testbot}"

seed_login_user() {
  echo "==> Seeding login user ${SEED_EMAIL} via ${SUT_BASE_URL}/api/auth/signup ..."
  local code
  code=$(curl -s -o /tmp/seed-signup.json -w '%{http_code}' -m 20 -X POST "${SUT_BASE_URL}/api/auth/signup" \
    -H 'content-type: application/json' \
    --data "{\"email\":\"${SEED_EMAIL}\",\"password\":\"${SEED_PASSWORD}\",\"username\":\"${SEED_USERNAME}\",\"language\":\"en\"}" \
    || echo 000)
  case "$code" in
    200|201) echo "==> Seed user created (${SEED_EMAIL} / ${SEED_PASSWORD})" ;;
    409|422) echo "==> Seed user already exists (HTTP ${code}) — ok" ;;
    *)       echo "!! WARN: signup returned HTTP ${code}: $(head -c 200 /tmp/seed-signup.json 2>/dev/null)" ;;
  esac
}

echo "==> Building Cal.com SUT from source + starting..."
docker compose "${COMPOSE[@]}" up -d --build

echo "==> Waiting for the web app on ${SUT_BASE_URL} (DB migrate + app-store seed run on first boot)..."
for i in $(seq 1 300); do
  if curl -fsS -m 5 -o /dev/null "${SUT_BASE_URL}"; then
    echo "==> SUT healthy"
    seed_login_user
    echo "==> Open ${SUT_BASE_URL}"
    exit 0
  fi
  sleep 5
  if [[ $i -eq 300 ]]; then
    echo "!! SUT failed to become healthy in time — recent logs:"
    docker compose "${COMPOSE[@]}" logs --tail 120 calcom
    exit 1
  fi
done
