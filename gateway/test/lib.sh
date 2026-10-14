# Helpers for the gateway smoke tests. Source this file; it runs nothing itself.
GATEWAY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="http://localhost:2000"
GH="https://api.github.com/repos/Rac0r/mugensame"
PASS=0
FAIL=0

load_env() {
  source "$GATEWAY_DIR/env.sh"
  : "${GITHUB_TOKEN:?set GITHUB_TOKEN in gateway/.env}"
}

# req METHOD PATH [curl args...] -> sets STATUS and BODY
req() {
  local method=$1 path=$2 out
  shift 2
  out=$(curl -s -w $'\n%{http_code}' -X "$method" "$BASE$path" "$@")
  STATUS=${out##*$'\n'}
  BODY=${out%$'\n'*}
}

# check DESCRIPTION ACTUAL EXPECTED
check() {
  if [ "$2" == "$3" ]; then
    PASS=$((PASS + 1)); echo "ok   - $1"
  else
    FAIL=$((FAIL + 1)); echo "FAIL - $1: expected '$3', got '$2'"
    [ -n "${BODY:-}" ] && echo "       last body: ${BODY:0:300}"
  fi
}

finish() {
  echo "$PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ]
}

port_pids() { lsof -ti tcp:2000 -sTCP:LISTEN 2>/dev/null; }

# start_gateway admin|now - uses the caller's environment, logs to gateway/test/gateway-<name>.log
start_gateway() {
  if [ -n "$(port_pids)" ]; then
    echo "port 2000 is busy - stop the running gateway first" >&2; exit 1
  fi
  "$GATEWAY_DIR/run-local.sh" "$1" > "$GATEWAY_DIR/test/gateway-$1.log" 2>&1 &
  GW_PID=$!
  disown "$GW_PID"
  for _ in $(seq 1 60); do
    curl -s -o /dev/null "$BASE/" && return 0
    sleep 1
  done
  kill_tree "$GW_PID"
  echo "gateway '$1' did not start, see gateway/test/gateway-$1.log" >&2; exit 1
}

# kill_tree PID - stops a process and all its descendants (membrane.sh starts java as a child)
kill_tree() {
  local child
  for child in $(pgrep -P "$1"); do kill_tree "$child"; done
  kill "$1" 2> /dev/null
}

stop_gateway() {
  local pids
  [ -n "${GW_PID:-}" ] && kill_tree "$GW_PID"
  pids=$(port_pids)
  [ -n "$pids" ] && kill $pids
  for _ in $(seq 1 30); do
    [ -z "$(port_pids)" ] && return 0
    sleep 1
  done
}

gh_api() {
  curl -s -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" "$@"
}

# gh_raw PATH - file content on branch admin-test
gh_raw() {
  curl -s -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github.raw+json" \
    -H "Cache-Control: no-cache" "$GH/contents/$1?ref=admin-test"
}

# gh_status PATH - HTTP status of the file on branch admin-test
gh_status() {
  curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Cache-Control: no-cache" "$GH/contents/$1?ref=admin-test"
}

reset_test_branch() {
  local main_sha
  gh_api -X DELETE "$GH/git/refs/heads/admin-test" > /dev/null
  main_sha=$(gh_api "$GH/git/ref/heads/main" | jq -r .object.sha)
  if ! gh_api -X POST "$GH/git/refs" -d "{\"ref\":\"refs/heads/admin-test\",\"sha\":\"$main_sha\"}" \
      | jq -e .ref > /dev/null; then
    echo "could not create branch admin-test - does GITHUB_TOKEN have Contents: read and write?" >&2
    exit 1
  fi
}

delete_test_branch() {
  gh_api -X DELETE "$GH/git/refs/heads/admin-test" > /dev/null
}
