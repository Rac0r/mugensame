#!/usr/bin/env bash
# Checks GET /now: normal response, a feed URL that returns 404 HTML, and a
# feed with exactly one item. Usage: gateway/test/now-smoke.sh (port 2000 and 8765 free)
set -uo pipefail
source "$(dirname "$0")/lib.sh"
load_env
TMP=$(mktemp -d)
trap 'stop_gateway; [ -n "${FEED_PID:-}" ] && kill "$FEED_PID"; rm -rf "$TMP"' EXIT

# --- normal
start_gateway now
req GET /now
check "/now -> 200" "$STATUS" 200
check "generatedAt is ISO" "$(jq -r '.generatedAt | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")' <<<"$BODY")" true
check "repos is a list" "$(jq -r '.repos | type' <<<"$BODY")" array
check "repo fields" "$(jq -c '.repos[0] | keys' <<<"$BODY")" '["description","name","pushedAt","url"]'
check "at most 5 repos" "$(jq -r '.repos | length <= 5' <<<"$BODY")" true
check "posts is a list" "$(jq -r '.posts | type' <<<"$BODY")" array
check "at most 3 posts" "$(jq -r '.posts | length <= 3' <<<"$BODY")" true
check "post fields" "$(jq -c '.posts[0] | keys' <<<"$BODY")" '["date","title","url"]'
check "post url is on the site" "$(jq -r '.posts[0].url | startswith("https://rac0r.github.io/mugensame/")' <<<"$BODY")" true
check "status is null or has text" "$(jq -r '.status == null or (.status.text | type == "string")' <<<"$BODY")" true
stop_gateway

# --- feed answers 404 HTML -> posts null, rest intact
(export FEED_URL=https://rac0r.github.io/mugensame/does-not-exist.xml; start_gateway now)
req GET /now
check "broken feed still 200" "$STATUS" 200
check "broken feed -> posts null" "$(jq -r '.posts' <<<"$BODY")" null
check "broken feed keeps repos" "$(jq -r '.repos | type' <<<"$BODY")" array
stop_gateway

# --- feed with exactly one item
cat > "$TMP/one.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"><channel><title>t</title>
<item><title>Only post</title><link>https://rac0r.github.io/mugensame/posts/only/</link>
<pubDate>Tue, 13 Oct 2026 00:00:00 GMT</pubDate><description>d</description></item>
</channel></rss>
EOF
python3 -m http.server 8765 --directory "$TMP" > /dev/null 2>&1 &
FEED_PID=$!
disown "$FEED_PID"
sleep 1
(export FEED_URL=http://localhost:8765/one.xml; start_gateway now)
req GET /now
check "single-item feed -> one post" "$(jq -r '.posts | length' <<<"$BODY")" 1
check "single-item title" "$(jq -r '.posts[0].title' <<<"$BODY")" "Only post"

finish
