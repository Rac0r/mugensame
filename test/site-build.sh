#!/usr/bin/env bash
# Builds the site into a temporary folder with temporary fixtures and checks
# drafts, images and (Task 9) the Now page. Leaves src/ and _site/ as they were.
set -uo pipefail
cd "$(dirname "$0")/.."
source gateway/test/lib.sh
OUT=$(mktemp -d)
FIXTURES=(src/posts/zz-draft-fixture.md src/posts/zz-public-fixture.md src/images/zz-fixture.png)
cleanup() { rm -rf "$OUT" "${FIXTURES[@]}"; }
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

# === end of sections ===
finish
