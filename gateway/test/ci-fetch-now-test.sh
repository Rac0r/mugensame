#!/usr/bin/env bash
# Runs gateway/ci-fetch-now.sh like the workflow does (needs Docker and port 2000 free).
set -uo pipefail
cd "$(dirname "$0")/../.."
source gateway/test/lib.sh
load_env
NOW_JSON=src/_data/now.json
BACKUP=$(mktemp)
HAD_FILE=no
[ -f "$NOW_JSON" ] && cp "$NOW_JSON" "$BACKUP" && HAD_FILE=yes
trap 'if [ "$HAD_FILE" = yes ]; then mv "$BACKUP" "$NOW_JSON"; else rm -f "$NOW_JSON" "$BACKUP"; fi' EXIT

gateway/ci-fetch-now.sh
check "success exit code" "$?" 0
check "now.json has repos" "$(jq -r '.repos | type' "$NOW_JSON")" array
check "now.json has generatedAt" "$(jq -r '.generatedAt | type' "$NOW_JSON")" string
check "no container left" "$(docker ps -q --filter ancestor=predic8/membrane:7.7.0 | wc -l | tr -d ' ')" 0

MEMBRANE_IMAGE=does-not-exist/membrane:0 gateway/ci-fetch-now.sh
check "failure still exits 0" "$?" 0
check "failure writes {}" "$(jq -c . "$NOW_JSON")" '{}'

finish
