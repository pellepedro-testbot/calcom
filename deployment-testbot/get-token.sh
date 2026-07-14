#!/usr/bin/env bash
# Best-effort auth for the Cal.com SUT.
#
# IMPORTANT: Cal.com authenticates the web app via a NextAuth **session cookie**
# (`next-auth.session-token`), NOT a bearer token. UI/DOM testbot flows should use the
# recorded browser session (storageState) and do NOT need this script. Cal.com's REST API
# v1 uses a per-user **API key** (`?apiKey=cal_live_...`), and API v2 uses OAuth access
# tokens — both require a seeded/registered user + key issuance, so there is no simple
# "print a bearer token" path from cold credentials.
#
# This script performs the NextAuth credentials login and prints the resulting session
# token (usable as a cookie). It requires a user to exist — cal.com's `start.sh` seeds only
# the app-store, not demo users, so seed users first (packages/prisma/seed.ts) or point
# CAL_EMAIL/CAL_PASSWORD at a registered account. If no user exists yet, this exits non-zero.
set -euo pipefail
BASE="${CAL_BASE_URL:-http://localhost:3000}"
EMAIL="${CAL_EMAIL:-[email protected]}"
PASSWORD="${CAL_PASSWORD:-[email protected]}"
JAR="$(mktemp)"; trap 'rm -f "$JAR"' EXIT

csrf="$(curl -fsS -c "$JAR" "$BASE/api/auth/csrf" | python3 -c "import json,sys;print(json.load(sys.stdin)['csrfToken'])")"

curl -fsS -c "$JAR" -b "$JAR" -X POST "$BASE/api/auth/callback/credentials" \
  -H 'content-type: application/x-www-form-urlencoded' \
  --data-urlencode "csrfToken=$csrf" \
  --data-urlencode "email=$EMAIL" \
  --data-urlencode "password=$PASSWORD" \
  --data-urlencode "redirect=false" \
  --data-urlencode "json=true" >/dev/null

token="$(awk '/next-auth\.session-token|__Secure-next-auth\.session-token/{print $7}' "$JAR" | tail -1)"
[ -n "$token" ] || { echo "no session token — is the user seeded/registered?" >&2; exit 1; }
printf '%s\n' "$token"
