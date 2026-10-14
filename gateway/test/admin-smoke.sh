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

# --- create post (Task 4)
SLUG="gateway-test-hello-1"
POST_BODY=$(jq -n '{title: "Gateway Test: Hello #1", description: "Created by admin-smoke.sh",
  tags: ["test", "say \"hi\""], body: "Hello from **Membrane**.", date: "2026-10-13"}')
req POST /admin/posts "${KEY[@]}" "${JSON[@]}" -d "$POST_BODY"
check "create -> 201" "$STATUS" 201
check "create returns slug" "$(jq -r .slug <<<"$BODY")" "$SLUG"
check "create returns path" "$(jq -r .path <<<"$BODY")" "src/posts/$SLUG.md"
check "create returns commit sha" "$(jq -r '.commit | length' <<<"$BODY")" 40
FILE=$(gh_raw "src/posts/$SLUG.md")
check "file starts with front matter" "$(sed -n 1p <<<"$FILE")" '---'
check "title is quoted" "$(sed -n 2p <<<"$FILE")" 'title: "Gateway Test: Hello #1"'
check "date line" "$(grep -c '^date: 2026-10-13$' <<<"$FILE")" 1
check "tag with quotes escaped" "$(grep -c '^  - "say \\"hi\\""$' <<<"$FILE")" 1
check "no draft line" "$(grep -c '^draft:' <<<"$FILE")" 0
check "body is last line" "$(tail -1 <<<"$FILE")" "Hello from **Membrane**."
check "front matter is valid YAML" \
  "$(sed -n '2,/^---$/p' <<<"$FILE" | sed '$d' | ruby -ryaml -rdate -e 'puts YAML.safe_load(STDIN.read, permitted_classes: [Date])["title"]')" \
  "Gateway Test: Hello #1"

req POST /admin/posts "${KEY[@]}" "${JSON[@]}" -d "$POST_BODY"
check "duplicate create -> 409" "$STATUS" 409

req POST /admin/posts "${KEY[@]}" "${JSON[@]}" -d '{"title":"Gateway Draft","description":"d","body":"b","draft":true}'
check "draft create -> 201" "$STATUS" 201
check "draft line present" "$(gh_raw src/posts/gateway-draft.md | grep -c '^draft: true$')" 1
check "date defaults to today (UTC)" \
  "$(gh_raw src/posts/gateway-draft.md | grep -c "^date: $(date -u +%F)$")" 1

req POST /admin/posts "${KEY[@]}" "${JSON[@]}" -d '{"title":"only title"}'
check "missing fields -> 400" "$STATUS" 400
req POST /admin/posts "${KEY[@]}" "${JSON[@]}" -d '{"title":"!!!","description":"d","body":"b"}'
check "title without letters -> 400" "$STATUS" 400
check "no empty-slug file" "$(gh_status src/posts/.md)" 404
req POST /admin/posts "${KEY[@]}" "${JSON[@]}" -d '{"title":"Bad date","description":"d","body":"b","date":"2026-13-45"}'
check "impossible date -> 400" "$STATUS" 400
check "bad-date post not committed" "$(gh_status src/posts/bad-date.md)" 404

# --- update + delete post (Task 5)
UPDATE_BODY=$(jq -n '{title: "Gateway Test: Hello #1", description: "Updated", body: "Changed body."}')
req PUT "/admin/posts/$SLUG" "${KEY[@]}" "${JSON[@]}" -d "$UPDATE_BODY"
check "update -> 200" "$STATUS" 200
check "update keeps slug" "$(jq -r .slug <<<"$BODY")" "$SLUG"
check "update returns commit sha" "$(jq -r '.commit | length' <<<"$BODY")" 40
check "file content replaced" "$(gh_raw "src/posts/$SLUG.md" | tail -1)" "Changed body."
req PUT /admin/posts/no-such-post "${KEY[@]}" "${JSON[@]}" -d "$UPDATE_BODY"
check "update missing -> 404" "$STATUS" 404
check "update did not create file" "$(gh_status src/posts/no-such-post.md)" 404
req PUT /admin/posts/Bad_Slug "${KEY[@]}" "${JSON[@]}" -d "$UPDATE_BODY"
check "update invalid slug -> 400" "$STATUS" 400
req PUT "/admin/posts/$SLUG" "${KEY[@]}" "${JSON[@]}" -d '{"title":"x"}'
check "update invalid body -> 400" "$STATUS" 400

req DELETE "/admin/posts/$SLUG" "${KEY[@]}"
check "delete -> 204" "$STATUS" 204
check "delete has empty body" "$BODY" ""
check "file is gone" "$(gh_status "src/posts/$SLUG.md")" 404
req DELETE "/admin/posts/$SLUG" "${KEY[@]}"
check "delete again -> 404" "$STATUS" 404
req DELETE /admin/posts/Bad_Slug "${KEY[@]}"
check "delete invalid slug -> 400" "$STATUS" 400

# === end of sections ===

# --- GitHub rejects the token -> 502 (Task 2). Restarts the gateway; keep last.
stop_gateway
(export GITHUB_TOKEN=invalid-token; start_gateway admin)
req GET /admin/posts "${KEY[@]}"
check "bad GitHub token -> 502" "$STATUS" 502
check "502 names GITHUB_TOKEN" "$(jq -r '.error | contains("GITHUB_TOKEN")' <<<"$BODY")" true
finish
