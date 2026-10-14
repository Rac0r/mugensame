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

# === end of sections ===

# --- GitHub rejects the token -> 502 (Task 2). Restarts the gateway; keep last.
stop_gateway
(export GITHUB_TOKEN=invalid-token; start_gateway admin)
req GET /admin/posts "${KEY[@]}"
check "bad GitHub token -> 502" "$STATUS" 502
check "502 names GITHUB_TOKEN" "$(jq -r '.error | contains("GITHUB_TOKEN")' <<<"$BODY")" true
finish
