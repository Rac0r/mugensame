#!/usr/bin/env bash
# Deploy workflow step: runs now.yaml in Docker and saves GET /now to
# src/_data/now.json for the Eleventy build. Never fails the build - on any
# problem it writes {} and the Now page shows "unavailable".
# Needs GITHUB_TOKEN; FEED_URL and MEMBRANE_IMAGE are optional.
set -uo pipefail
cd "$(dirname "$0")/.."
OUT=src/_data/now.json
IMAGE="${MEMBRANE_IMAGE:-predic8/membrane:7.7.0}"
export FEED_URL="${FEED_URL:-https://rac0r.github.io/mugensame/feed.xml}"

fallback() {
  echo "::warning::Now page data unavailable: $1"
  echo '{}' > "$OUT"
  exit 0
}

cid=$(docker run -d -p 2000:2000 -e GITHUB_TOKEN -e FEED_URL \
  -v "$PWD/gateway:/opt/membrane/work" -w /opt/membrane/work \
  --entrypoint /opt/membrane/membrane.sh "$IMAGE" -c now.yaml) || fallback "could not start $IMAGE"
trap 'docker rm -f "$cid" > /dev/null 2>&1' EXIT

for _ in $(seq 1 60); do
  curl -s -o /dev/null http://localhost:2000/ && break
  sleep 1
done

if curl -sf http://localhost:2000/now -o "$OUT.tmp" && jq -e 'type == "object"' "$OUT.tmp" > /dev/null; then
  mv "$OUT.tmp" "$OUT"
  echo "Saved $OUT"
else
  rm -f "$OUT.tmp"
  docker logs "$cid" 2>&1 | tail -40
  fallback "GET /now failed"
fi
