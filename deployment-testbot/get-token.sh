#!/usr/bin/env bash
# Auth token for the Cal.com SUT — a NextAuth **session cookie** (not a bearer token).
#
# Performs the NextAuth credentials login as the user that setup.sh seeds (see seed_login_user)
# and prints the resulting `next-auth.session-token`. The account exists by the time testbot
# calls authTokenCommand because setup.sh seeds it right after the SUT becomes healthy.
# Override CAL_EMAIL / CAL_PASSWORD (and CAL_BASE_URL / SUT_BASE_URL) to use a different account.
set -euo pipefail
BASE="${CAL_BASE_URL:-${SUT_BASE_URL:-http://localhost:3000}}"
EMAIL="${CAL_EMAIL:-testbot@dev.local}"
PASSWORD="${CAL_PASSWORD:-Testb0t-Pass123!}"
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
[ -n "$token" ] || { echo "no session token — is the seed user present? (setup.sh seed_login_user)" >&2; exit 1; }
printf '%s\n' "$token"
