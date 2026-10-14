#!/usr/bin/env bash
# Builds the site into a temporary folder with temporary fixtures and checks
# drafts, images and (Task 9) the Now page. Leaves src/ and _site/ as they were.
set -uo pipefail
cd "$(dirname "$0")/.."
source gateway/test/lib.sh
OUT=$(mktemp -d)
FIXTURES=(src/posts/zz-draft-fixture.md src/posts/zz-public-fixture.md src/images/zz-fixture.png)
NOW_JSON=src/_data/now.json
[ -f "$NOW_JSON" ] && cp "$NOW_JSON" "$OUT.now-backup"
cleanup() {
  rm -rf "$OUT" "${FIXTURES[@]}" "$NOW_JSON"
  [ -f "$OUT.now-backup" ] && mv "$OUT.now-backup" "$NOW_JSON"
}
trap cleanup EXIT

build() {
  rm -rf "$OUT"/*
  npx @11ty/eleventy --output="$OUT" --quiet > /dev/null
}

cat > src/posts/zz-draft-fixture.md <<'EOF'
---
title: Draft fixture
description: d
date: 2026-10-13
draft: true
---

draft
EOF
cat > src/posts/zz-public-fixture.md <<'EOF'
---
title: Public fixture
description: d
date: 2026-10-13
---

public
EOF
printf 'png-bytes' > src/images/zz-fixture.png

# --- drafts + images (Task 7)
build
check "public post is built" "$([ -f "$OUT/posts/zz-public-fixture/index.html" ] && echo yes)" yes
check "draft post is not built" "$([ -e "$OUT/posts/zz-draft-fixture" ] && echo built || echo absent)" absent
check "draft not in feed" "$(grep -c 'zz-draft-fixture' "$OUT/feed.xml")" 0
check "image copied" "$(cmp -s "$OUT/images/zz-fixture.png" src/images/zz-fixture.png && echo same)" same

# --- Now page (Task 9)
cat > "$NOW_JSON" <<'EOF'
{
  "generatedAt": "2026-10-13T10:00:00Z",
  "status": { "text": "Learning <b>Membrane</b>", "updatedAt": "2026-10-12T09:00:00Z" },
  "repos": [ { "name": "dotfiles", "description": "zsh & tmux", "url": "https://github.com/Rac0r/dotfiles", "pushedAt": "2026-10-11T08:00:00Z" } ],
  "posts": [ { "title": "Dotfiles", "url": "https://rac0r.github.io/mugensame/posts/dotfiles/", "date": "Fri, 26 Jun 2026 00:00:00 GMT" } ]
}
EOF
build
PAGE="$OUT/now/index.html"
check "now page built" "$([ -f "$PAGE" ] && echo yes)" yes
check "status text escaped" "$(grep -c 'Learning &lt;b&gt;Membrane&lt;/b&gt;' "$PAGE")" 1
check "no raw HTML from status" "$(grep -c '<b>Membrane</b>' "$PAGE")" 0
check "repo linked" "$(grep -c 'href="https://github.com/Rac0r/dotfiles"' "$PAGE")" 1
check "post linked" "$(grep -c 'href="https://rac0r.github.io/mugensame/posts/dotfiles/"' "$PAGE")" 1
check "nav links to now" "$(grep -c 'href="/mugensame/now/"' "$OUT/index.html")" 1

echo '{"generatedAt":"2026-10-13T10:00:00Z","status":null,"repos":[],"posts":null}' > "$NOW_JSON"
build
check "null status -> unavailable" "$(grep -c 'Status unavailable' "$OUT/now/index.html")" 1
check "empty repos -> unavailable" "$(grep -c 'Repository activity unavailable' "$OUT/now/index.html")" 1
check "null posts -> unavailable" "$(grep -c 'Posts unavailable' "$OUT/now/index.html")" 1

echo '{}' > "$NOW_JSON"
build
check "empty object -> page still built" "$(grep -c 'Status unavailable' "$OUT/now/index.html")" 1

rm -f "$NOW_JSON"
build
check "missing now.json -> page still built" "$(grep -c 'Posts unavailable' "$OUT/now/index.html")" 1

# === end of sections ===
finish
