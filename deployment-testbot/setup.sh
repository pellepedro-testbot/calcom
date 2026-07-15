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

# Event type to seed so booking tests have data (first EventType row → id=1, which the
# generated createBookingFlow/checkBookingAvailability tests use). Postgres service is `database`.
SEED_ET_TITLE="${SEED_ET_TITLE:-Testbot 30 Min}"
SEED_ET_SLUG="${SEED_ET_SLUG:-testbot-30min}"
SEED_ET_LENGTH="${SEED_ET_LENGTH:-30}"
PSQL=(docker compose "${COMPOSE[@]}" exec -T database psql -U unicorn_user -d calendso)

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

seed_event_type() {
  echo "==> Seeding event type '${SEED_ET_SLUG}' for ${SEED_EMAIL} (booking tests use eventTypeId=1) ..."
  "${PSQL[@]}" -v ON_ERROR_STOP=0 -c "
    INSERT INTO \"EventType\" (title, slug, length, \"userId\")
    SELECT '${SEED_ET_TITLE}', '${SEED_ET_SLUG}', ${SEED_ET_LENGTH}, u.id
    FROM users u WHERE u.email='${SEED_EMAIL}'
      AND NOT EXISTS (SELECT 1 FROM \"EventType\" et WHERE et.slug='${SEED_ET_SLUG}' AND et.\"userId\"=u.id);
    INSERT INTO \"_user_eventtype\" (\"A\",\"B\")
    SELECT et.id, u.id FROM \"EventType\" et JOIN users u ON u.id=et.\"userId\"
    WHERE et.slug='${SEED_ET_SLUG}'
      AND NOT EXISTS (SELECT 1 FROM \"_user_eventtype\" j WHERE j.\"A\"=et.id AND j.\"B\"=u.id);
  " >/dev/null 2>&1 || echo "!! WARN: event-type seed SQL failed (non-fatal)"
  local etid
  etid=$("${PSQL[@]}" -tAc "SELECT id FROM \"EventType\" WHERE slug='${SEED_ET_SLUG}' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
  echo "==> Event type seeded: id=${etid:-?} slug=${SEED_ET_SLUG} (public page: ${SUT_BASE_URL}/${SEED_USERNAME}/${SEED_ET_SLUG})"
}

echo "==> Building Cal.com SUT from source + starting..."
docker compose "${COMPOSE[@]}" up -d --build

echo "==> Waiting for the web app on ${SUT_BASE_URL} (DB migrate + app-store seed run on first boot)..."
for i in $(seq 1 300); do
  if curl -fsS -m 5 -o /dev/null "${SUT_BASE_URL}"; then
    echo "==> SUT healthy"
    seed_login_user
    seed_event_type
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
