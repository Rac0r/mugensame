#!/usr/bin/env bash
# Runs every admin API check against the throwaway branch admin-test, which is
# recreated from main first and deleted afterwards. Nothing gets deployed.
# Usage: gateway/test/admin-smoke.sh   (needs gateway/.env and a free port 2000)
set -uo pipefail
source "$(dirname "$0")/lib.sh"
load_env
: "${ADMIN_API_KEY:?set ADMIN_API_KEY in gateway/.env}"
export GITHUB_BRANCH=admin-test
KEY=(-H "X-Api-Key: $ADMIN_API_KEY")
JSON=(-H "Content-Type: application/json")

reset_test_branch
trap 'stop_gateway; delete_test_branch' EXIT
start_gateway admin

# --- startup guard (Task 1)
(export ADMIN_API_KEY=""; "$GATEWAY_DIR/run-local.sh" admin > /dev/null 2>&1)
check "empty ADMIN_API_KEY refuses to start" "$([ $? -ne 0 ] && echo refused)" refused

# --- auth + list posts (Task 1)
req GET /admin/posts
check "no key -> 401" "$STATUS" 401
req GET /admin/posts -H "X-Api-Key: wrong"
check "wrong key -> 403" "$STATUS" 403
req GET /admin/posts "${KEY[@]}"
check "list -> 200" "$STATUS" 200
check "list contains first" "$(jq -r '[.[].slug] | index("first") != null' <<<"$BODY")" true
check "list entries are {slug, sha}" "$(jq -c '.[0] | keys' <<<"$BODY")" '["sha","slug"]'
check "posts.json is not listed" "$(jq -r '[.[].slug] | index("posts") == null' <<<"$BODY")" true

# --- read one post + error mapping (Task 2)
req GET /admin/posts/first "${KEY[@]}"
check "read -> 200" "$STATUS" 200
check "read returns front matter" "$(head -1 <<<"$BODY")" '---'
check "read contains title" "$(grep -c '^title: First Post$' <<<"$BODY")" 1
req GET /admin/posts/does-not-exist "${KEY[@]}"
check "read missing -> 404" "$STATUS" 404
check "404 body is mapped" "$(jq -r .error <<<"$BODY")" "Not found"
check "404 keeps GitHub status" "$(jq -r .githubStatus <<<"$BODY")" 404

# --- status (Task 3)
req PUT /admin/status "${KEY[@]}" "${JSON[@]}" -d '{"text":"testing the gateway"}'
check "status first write -> 200" "$STATUS" 200
check "status echoes text" "$(jq -r .text <<<"$BODY")" "testing the gateway"
check "status has ISO updatedAt" "$(jq -r '.updatedAt | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")' <<<"$BODY")" true
check "status file committed" "$(gh_raw src/_data/status.json | jq -r .text)" "testing the gateway"
req PUT /admin/status "${KEY[@]}" "${JSON[@]}" -d '{"text":"second: with \"quotes\""}'
check "status overwrite -> 200" "$STATUS" 200
check "status file overwritten" "$(gh_raw src/_data/status.json | jq -r .text)" 'second: with "quotes"'
req PUT /admin/status "${KEY[@]}" "${JSON[@]}" -d '{"text":""}'
check "empty status -> 400" "$STATUS" 400
req PUT /admin/status "${KEY[@]}" "${JSON[@]}" -d '{"text":"x","extra":1}'
check "unknown field -> 400" "$STATUS" 400

# === end of sections ===

# --- GitHub rejects the token -> 502 (Task 2). Restarts the gateway; keep last.
stop_gateway
(export GITHUB_TOKEN=invalid-token; start_gateway admin)
req GET /admin/posts "${KEY[@]}"
check "bad GitHub token -> 502" "$STATUS" 502
check "502 names GITHUB_TOKEN" "$(jq -r '.error | contains("GITHUB_TOKEN")' <<<"$BODY")" true
finish
