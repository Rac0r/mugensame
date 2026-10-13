# Membrane Site API Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a local Membrane admin API that manages posts, images and a status line through GitHub commits, and a `/now` aggregator that fills a new Now page during the GitHub Actions build.

**Architecture:** Two Membrane 7.7 YAML configs in `gateway/`: `admin.yaml` (local only, API-key protected, rewrites requests into GitHub contents API calls) and `now.yaml` (read-only, three `call:`s merged into one JSON). Small Groovy scripts in `gateway/scripts/` do what YAML cannot (base64, front matter, JSON reshaping, status mapping). The Eleventy site gains a drafts preprocessor, an images passthrough and a `now.njk` page; the deploy workflow runs `now.yaml` in Docker before building.

**Tech Stack:** Membrane API Gateway 7.7.0 (YAML config, Groovy 4 scripts, SpEL/JSONPath expressions), GitHub REST API (contents, git refs, users), Eleventy 3.1 + Nunjucks, Bash + curl + jq for tests, Docker (`predic8/membrane:7.7.0`) and GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-13-membrane-site-api-design.md`. Read its section "Membrane 7.7 behaviour this design relies on" before writing any YAML; every rule there was verified with probe configs.

## Global Constraints

- Repo root for every path below: `~/Developer/Coding/Projekte/mugensame`. Work on branch `feat/membrane-gateway` (created in Task 1 from `docs/gateway-spec`).
- Membrane version exactly 7.7.0: local distribution at `~/Developer/Tutorials/membrane` (`MEMBRANE_HOME`), Docker image `predic8/membrane:7.7.0`. Java 21+ locally.
- GitHub repository `Rac0r/mugensame`; GitHub user `Rac0r`; live site `https://rac0r.github.io/mugensame/`; Eleventy `pathPrefix` is `/mugensame/`.
- Both configs listen on port **2000**. Only one runs at a time.
- `admin.yaml` never runs in CI. `now.yaml` contains no write routes and no admin key.
- Tests never commit to `main`: `admin-smoke.sh` uses branch `admin-test`, recreated from `main` and deleted afterwards.
- Every Groovy script ends with `CONTINUE` or returns a `Response` — otherwise its last value replaces the message body.
- In `template:` sources with `contentType: application/json`, write `${...}` placeholders without quotes.
- Commit messages created by the admin API, verbatim: `admin: create post <slug>`, `admin: update post <slug>`, `admin: delete post <slug>`, `admin: add image <filename>`, `admin: update status`.
- Image filenames match `^[a-z0-9][a-z0-9._-]*\.(png|jpe?g|gif|webp|svg)$`; image bodies at most 5 MB (5 × 1024 × 1024 bytes).
- Every git commit message in this plan ends with the line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` after a blank line.
- Do not push, open a PR or merge to `main` without asking the user: pushing to `main` deploys the live site.

## Review Focus

1. Titles, descriptions and tags containing YAML-significant characters (`:`, `#`, `"`, leading `-`) must still produce valid front matter that Eleventy parses — Task 4 tests a title with `:` and `#` and a quoted tag.
2. A title that contains no `a-z`/`0-9` characters (e.g. `"!!!"`), or a path slug like `Bad_Slug`, must be rejected with 400 instead of committing `src/posts/.md` or an unexpected path — Tasks 4 and 5.
3. A syntactically valid but impossible date (`2026-13-45`) must be rejected with 400, not committed and break the next build — Task 4.
4. A feed with exactly one item (xml2Json yields an object, not a list) must still produce a one-element `posts` list — Task 8.
5. Status text or repo descriptions containing HTML must be shown escaped on the Now page — Task 9.

---

### Task 1: Gateway scaffolding, test harness, API key and `GET /admin/posts`

**Files:**
- Create: `gateway/.env.example`, `gateway/env.sh`, `gateway/run-local.sh`, `gateway/admin.yaml`, `gateway/scripts/list-posts.groovy`, `gateway/test/lib.sh`, `gateway/test/admin-smoke.sh`, `gateway/README.md`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `gateway/run-local.sh admin|now` — starts the config natively on port 2000; environment variables already set win over `gateway/.env`.
  - `gateway/test/lib.sh` functions: `load_env`, `req METHOD PATH [curl args…]` (sets `STATUS`, `BODY`), `check DESCRIPTION ACTUAL EXPECTED`, `finish`, `start_gateway admin|now`, `stop_gateway`, `gh_api [curl args…]`, `gh_raw PATH`, `gh_status PATH`, `reset_test_branch`, `delete_test_branch`; variables `GATEWAY_DIR`, `BASE`, `GH`.
  - `admin-smoke.sh` arrays `KEY` (API key header) and `JSON` (content type header) and the marker line `# === end of sections ===` that later tasks insert above.
  - `admin.yaml` `global:` block (API key + GitHub headers) that every later route relies on.

- [ ] **Step 0: Human setup (ask the user to do this; do not create tokens yourself)**

The user creates `gateway/.env` from `gateway/.env.example` (written in Step 3) with:
- `GITHUB_TOKEN`: GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token. Repository access: *Only select repositories* → `Rac0r/mugensame`. Permissions → Repository permissions → **Contents: Read and write**. Expiration: at most one year.
- `ADMIN_API_KEY`: output of `openssl rand -hex 24`.

Continue with Steps 1–3 while waiting; Step 5 needs the file.

- [ ] **Step 1: Create the branch**

```bash
cd ~/Developer/Coding/Projekte/mugensame
git switch -c feat/membrane-gateway
```

- [ ] **Step 2: Write the test harness**

`gateway/test/lib.sh`:

```bash
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
  for _ in $(seq 1 60); do
    curl -s -o /dev/null "$BASE/" && return 0
    sleep 1
  done
  echo "gateway '$1' did not start, see gateway/test/gateway-$1.log" >&2; exit 1
}

stop_gateway() {
  local pids
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
```

`gateway/test/admin-smoke.sh`:

```bash
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
check "wrong key -> 401" "$STATUS" 401
req GET /admin/posts "${KEY[@]}"
check "list -> 200" "$STATUS" 200
check "list contains first" "$(jq -r '[.[].slug] | index("first") != null' <<<"$BODY")" true
check "list entries are {slug, sha}" "$(jq -c '.[0] | keys' <<<"$BODY")" '["sha","slug"]'
check "posts.json is not listed" "$(jq -r '[.[].slug] | index("posts") == null' <<<"$BODY")" true

# === end of sections ===
finish
```

```bash
chmod +x gateway/test/admin-smoke.sh
```

- [ ] **Step 3: Write env handling, launcher, example env, README, ignores**

`gateway/env.sh`:

```bash
# Loads gateway/.env without overriding variables that are already set, so
# `GITHUB_BRANCH=admin-test ./run-local.sh admin` wins over the file, and an
# explicitly empty variable stays empty. Source it with GATEWAY_DIR set.
if [ -f "$GATEWAY_DIR/.env" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|\#*) continue ;; esac
    key=${line%%=*}
    value=${line#*=}
    if [ -z "${!key+x}" ]; then export "$key=$value"; fi
  done < "$GATEWAY_DIR/.env"
fi
: "${MEMBRANE_HOME:=$HOME/Developer/Tutorials/membrane}"
: "${GITHUB_BRANCH:=main}"
: "${FEED_URL:=https://rac0r.github.io/mugensame/feed.xml}"
export MEMBRANE_HOME GITHUB_BRANCH FEED_URL
```

`gateway/run-local.sh`:

```bash
#!/usr/bin/env bash
# Starts a gateway config with the local Membrane distribution:
#   ./run-local.sh admin   admin API on http://localhost:2000/admin/...
#   ./run-local.sh now     aggregator on http://localhost:2000/now
set -euo pipefail
GATEWAY_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$GATEWAY_DIR/env.sh"

config="${1:-}"
case "$config" in
  admin|now) ;;
  *) echo "usage: $0 admin|now" >&2; exit 2 ;;
esac
: "${GITHUB_TOKEN:?set GITHUB_TOKEN in gateway/.env}"
if [ "$config" = admin ]; then
  : "${ADMIN_API_KEY:?set ADMIN_API_KEY in gateway/.env}"
fi

cd "$GATEWAY_DIR"
exec "$MEMBRANE_HOME/membrane.sh" -c "$config.yaml"
```

```bash
chmod +x gateway/run-local.sh
```

`gateway/.env.example`:

```bash
# Copy to gateway/.env (git-ignored) and fill in. Variables already set in the
# environment win over this file.

# Fine-grained personal access token: repository Rac0r/mugensame only,
# permission "Contents: Read and write".
GITHUB_TOKEN=
# Secret for the X-Api-Key header. Generate with: openssl rand -hex 24
ADMIN_API_KEY=
# Branch the admin API commits to (tests use admin-test).
GITHUB_BRANCH=main
# Published RSS feed read by /now.
FEED_URL=https://rac0r.github.io/mugensame/feed.xml
# Unpacked Membrane 7.7.0 distribution. Defaults to ~/Developer/Tutorials/membrane.
# MEMBRANE_HOME=
```

`gateway/README.md`:

````markdown
# mugensame gateway

Membrane API Gateway 7.7 configs for the site. Design:
`docs/superpowers/specs/2026-10-13-membrane-site-api-design.md`.

| Config | Runs | Purpose |
|---|---|---|
| `admin.yaml` | your laptop only | Admin API: posts, images, status → commits on GitHub |
| `now.yaml` | GitHub Actions + laptop | `GET /now` for the Now page |

## Setup

1. Java 21+ and the Membrane 7.7.0 distribution in `~/Developer/Tutorials/membrane`
   (or set `MEMBRANE_HOME`).
2. `cp gateway/.env.example gateway/.env` and fill in `GITHUB_TOKEN` and `ADMIN_API_KEY`
   (instructions in the file).

## Run

```sh
gateway/run-local.sh admin    # http://localhost:2000/admin/...
gateway/run-local.sh now      # http://localhost:2000/now
```

YAML and script changes reload without a restart.

## Admin API

Every request needs `X-Api-Key: <ADMIN_API_KEY>`. Every write is one commit on
`GITHUB_BRANCH` (default `main`, which deploys the site).

| Request | Body | Result |
|---|---|---|
| `GET /admin/posts` | — | `[{slug, sha}]` |
| `GET /admin/posts/{slug}` | — | Markdown |
| `POST /admin/posts` | `{title, description, body, tags?, date?, draft?}` | 201 `{slug, path, commit}` |
| `PUT /admin/posts/{slug}` | same as POST | 200 `{slug, path, commit}` |
| `DELETE /admin/posts/{slug}` | — | 204 |
| `PUT /admin/images/{filename}` | image bytes, `Content-Type: image/*`, ≤ 5 MB | 201 `{url}` |
| `PUT /admin/status` | `{text}` | 200 `{text, updatedAt}` |

Example:

```sh
source gateway/.env
curl -X POST localhost:2000/admin/posts -H "X-Api-Key: $ADMIN_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"title":"Hello","description":"First post via the gateway","tags":["gateway"],"body":"Hi!"}'
```

## Tests

```sh
gateway/test/admin-smoke.sh   # all admin routes, on throwaway branch admin-test
gateway/test/now-smoke.sh     # /now, including failure cases
test/site-build.sh            # drafts, images, Now page rendering
```
````

Append to `.gitignore`:

```
gateway/.env
gateway/test/*.log
```

- [ ] **Step 4: Write a minimal `admin.yaml` without routes**

`gateway/admin.yaml`:

```yaml
# yaml-language-server: $schema=https://www.membrane-api.io/v7.7.0.json
# Admin API for mugensame - local only, never deploy this file.
# Every request needs X-Api-Key; Membrane then calls the GitHub contents API
# with GITHUB_TOKEN and commits to GITHUB_BRANCH. Start: gateway/run-local.sh admin
global:
  - apiKey:
      stores:
        - simple:
            - secret:
                value: "#{env.ADMIN_API_KEY}"
      extractors:
        - header: X-Api-Key
  - request:
      - headerFilter:
          - exclude: x-api-key
      - setHeader:
          name: Authorization
          value: "Bearer #{env.GITHUB_TOKEN}"
      - setHeader:
          name: Accept
          value: application/vnd.github+json
      - setHeader:
          name: X-GitHub-Api-Version
          value: "2022-11-28"
      - setHeader:
          name: User-Agent
          value: mugensame-gateway
```

- [ ] **Step 5: Run the tests to verify they fail**

Run: `gateway/test/admin-smoke.sh`
Expected: exits early with `gateway 'admin' did not start` — `admin.yaml` defines no API yet, so nothing listens on port 2000. (The test branch is still cleaned up by the trap.)

- [ ] **Step 6: Add the list route and its script**

Append to `gateway/admin.yaml`:

```yaml
---
# GET /admin/posts -> [{slug, sha}] of src/posts/*.md
api:
  name: list-posts
  port: 2000
  method: GET
  path:
    uri: /admin/posts
  flow:
    - response:
        - groovy:
            location: scripts/list-posts.groovy
  target:
    url: "https://api.github.com/repos/Rac0r/mugensame/contents/src/posts?ref=#{env.GITHUB_BRANCH}"
```

`gateway/scripts/list-posts.groovy`:

```groovy
// GET /admin/posts: turns GitHub's listing of src/posts into [{slug, sha}] for
// Markdown files. Error responses are left to github-errors.groovy.
import groovy.json.JsonOutput
import groovy.json.JsonSlurper

def res = exchange.response
if (res.statusCode >= 400) return CONTINUE

def entries = new JsonSlurper().parseText(res.bodyAsStringDecoded)
def posts = entries
        .findAll { it.type == 'file' && it.name.endsWith('.md') }
        .collect { [slug: it.name[0..-4], sha: it.sha] }
res.setBodyContent(JsonOutput.toJson(posts).getBytes('UTF-8'))
res.header.setContentType('application/json')
CONTINUE
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `gateway/test/admin-smoke.sh`
Expected: `7 passed, 0 failed`. If `list contains first` fails, read `gateway/test/gateway-admin.log`; a Groovy compile error there means a script typo, a 401 from GitHub means the token lacks access to `Rac0r/mugensame`.

- [ ] **Step 8: Commit**

```bash
git add .gitignore gateway/
git status --short   # gateway/.env must NOT be listed
git commit -m "feat(gateway): admin API skeleton with API key and post listing

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `GET /admin/posts/{slug}` and GitHub error mapping

**Files:**
- Create: `gateway/scripts/github-errors.groovy`
- Modify: `gateway/admin.yaml` (global block, new route), `gateway/test/admin-smoke.sh`

**Interfaces:**
- Consumes: Task 1 `global:` block, `lib.sh` helpers, `KEY`.
- Produces: `github-errors.groovy` runs on every admin response and rewrites only GitHub error bodies (those with `documentation_url` on `docs.github.com`) to `{error, githubStatus, githubMessage}` with status 409 (GitHub 409/422), 404 (404) or 502 (401/403 → error text mentions `GITHUB_TOKEN`; anything else). Membrane's own 400/401 responses pass unchanged. Later tasks rely on 422→409 and 404→404.

- [ ] **Step 1: Write the failing tests**

Insert above `# === end of sections ===` in `gateway/test/admin-smoke.sh`:

```bash
# --- read one post + error mapping (Task 2)
req GET /admin/posts/first "${KEY[@]}"
check "read -> 200" "$STATUS" 200
check "read returns front matter" "$(head -1 <<<"$BODY")" '---'
check "read contains title" "$(grep -c '^title: First Post$' <<<"$BODY")" 1
req GET /admin/posts/does-not-exist "${KEY[@]}"
check "read missing -> 404" "$STATUS" 404
check "404 body is mapped" "$(jq -r .error <<<"$BODY")" "Not found"
check "404 keeps GitHub status" "$(jq -r .githubStatus <<<"$BODY")" 404
```

Insert below `# === end of sections ===` and above `finish` (it restarts the gateway, so it stays last):

```bash
# --- GitHub rejects the token -> 502 (Task 2). Restarts the gateway; keep last.
stop_gateway
(export GITHUB_TOKEN=invalid-token; start_gateway admin)
req GET /admin/posts "${KEY[@]}"
check "bad GitHub token -> 502" "$STATUS" 502
check "502 names GITHUB_TOKEN" "$(jq -r '.error | contains("GITHUB_TOKEN")' <<<"$BODY")" true
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `gateway/test/admin-smoke.sh`
Expected: the read checks FAIL (`/admin/posts/first` either gets 404 or is answered by the list route as a path prefix), and so do `404 body is mapped`, `404 keeps GitHub status`, `bad GitHub token -> 502` (GitHub's 401 passes through) and `502 names GITHUB_TOKEN`. Task 1 checks still pass.

- [ ] **Step 3: Implement**

`gateway/scripts/github-errors.groovy`:

```groovy
// Runs on every admin API response. Rewrites GitHub error responses into this
// API's errors (spec: "Error mapping"); everything else - successes and
// Membrane's own 400/401 problem responses - passes unchanged.
import groovy.json.JsonOutput
import groovy.json.JsonSlurper

def res = exchange.response
if (res == null || res.statusCode < 400) return CONTINUE

def gh
try {
    gh = new JsonSlurper().parseText(res.bodyAsStringDecoded)
} catch (ignored) {
    return CONTINUE
}
if (!(gh instanceof Map) || !(gh.documentation_url ?: '').contains('docs.github.com')) return CONTINUE

int githubStatus = res.statusCode
int status
String error
switch (githubStatus) {
    case 409:
    case 422:
        status = 409
        error = 'Conflict: the file already exists or was changed in the meantime'
        break
    case 404:
        status = 404
        error = 'Not found'
        break
    case 401:
    case 403:
        status = 502
        error = 'GitHub rejected the request - check GITHUB_TOKEN (needs Contents: read and write on Rac0r/mugensame)'
        break
    default:
        status = 502
        error = 'GitHub error'
}

res.statusCode = status
res.statusMessage = [404: 'Not Found', 409: 'Conflict', 502: 'Bad Gateway'][status]
res.setBodyContent(JsonOutput.toJson([error: error, githubStatus: githubStatus, githubMessage: gh.message]).getBytes('UTF-8'))
res.header.setContentType('application/json')
CONTINUE
```

Append to the `global:` list in `gateway/admin.yaml` (after the `- request:` block, same indentation):

```yaml
  - response:
      - groovy:
          location: scripts/github-errors.groovy
```

Append a route to `gateway/admin.yaml`:

```yaml
---
# GET /admin/posts/{slug} -> raw Markdown of src/posts/{slug}.md
api:
  name: read-post
  port: 2000
  method: GET
  path:
    uri: /admin/posts/{slug}
  flow:
    - request:
        - setHeader:
            name: Accept
            value: application/vnd.github.raw+json
  target:
    url: "https://api.github.com/repos/Rac0r/mugensame/contents/src/posts/${pathParam.slug}.md?ref=#{env.GITHUB_BRANCH}"
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `gateway/test/admin-smoke.sh`
Expected: `0 failed`. If `read returns front matter` gets JSON, the route's `setHeader` did not override the global `Accept` — check the indentation of the route's `flow:`.

- [ ] **Step 5: Commit**

```bash
git add gateway/
git commit -m "feat(gateway): read a post and map GitHub errors

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `PUT /admin/status` and the shared commit pipeline

**Files:**
- Create: `gateway/scripts/read-sha.groovy`, `gateway/scripts/commit-body.groovy`, `gateway/scripts/commit-response.groovy`, `gateway/scripts/status-file.groovy`, `gateway/schemas/status.json`
- Modify: `gateway/admin.yaml`, `gateway/test/admin-smoke.sh`

**Interfaces:**
- Consumes: global block, `github-errors.groovy`, `gh_raw`.
- Produces — the commit pipeline every write route uses:
  1. A route script sets exchange properties: `path` (repo path, String), `content` (String or `byte[]`; absent for deletes), `message` (commit message), `successStatus` (int), `result` (Map returned to the client; a `commit` key is filled with the commit sha).
  2. Optional `call:` GET `contents/${property.path}` followed by `read-sha.groovy` → `property.sha` (String or null).
  3. `commit-body.groovy` → request body `{message, branch, content?, sha?}`.
  4. `target:` PUT or DELETE `contents/${property.path}`.
  5. `commit-response.groovy` in `response:` → status `successStatus`, body `result` (empty for 204).

- [ ] **Step 1: Write the failing tests**

Insert above `# === end of sections ===`:

```bash
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `gateway/test/admin-smoke.sh`
Expected: the status checks FAIL (404, no route); earlier checks pass.

- [ ] **Step 3: Implement**

`gateway/schemas/status.json`:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["text"],
  "additionalProperties": false,
  "properties": {
    "text": { "type": "string", "minLength": 1, "maxLength": 280 }
  }
}
```

`gateway/scripts/status-file.groovy`:

```groovy
// PUT /admin/status: prepares src/_data/status.json for the commit pipeline
// (see commit-body.groovy). The body was already checked by schemas/status.json.
import groovy.json.JsonOutput
import groovy.json.JsonSlurper
import java.time.Instant
import java.time.temporal.ChronoUnit

def input = new JsonSlurper().parseText(exchange.request.bodyAsStringDecoded)
def file = [text: input.text, updatedAt: Instant.now().truncatedTo(ChronoUnit.SECONDS).toString()]

property.path = 'src/_data/status.json'
property.content = JsonOutput.prettyPrint(JsonOutput.toJson(file)) + '\n'
property.message = 'admin: update status'
property.successStatus = 200
property.result = file
CONTINUE
```

`gateway/scripts/read-sha.groovy`:

```groovy
// After a `call:` to GET contents/<path>: stores the file's blob sha in
// property.sha, or null when GitHub answered with an error (e.g. 404 because
// the file does not exist). `call:` hides the status code, so the body decides.
import groovy.json.JsonSlurper

property.sha = null
try {
    def meta = new JsonSlurper().parseText(exchange.request.bodyAsStringDecoded)
    if (meta instanceof Map && meta.sha) property.sha = meta.sha
} catch (ignored) {
}
CONTINUE
```

`gateway/scripts/commit-body.groovy`:

```groovy
// Builds the request body for GitHub's "create or update file contents" and
// "delete a file" endpoints from properties set by the route's own script:
//   property.message  commit message
//   property.content  String or byte[]; absent for deletes
//   property.sha      current blob sha; absent/null when creating
import groovy.json.JsonOutput

def body = [message: property.message, branch: System.getenv('GITHUB_BRANCH') ?: 'main']
if (property.content != null) {
    byte[] bytes = property.content instanceof byte[] ? property.content : property.content.toString().getBytes('UTF-8')
    body.content = bytes.encodeBase64().toString()
}
if (property.sha) body.sha = property.sha

exchange.request.setBodyContent(JsonOutput.toJson(body).getBytes('UTF-8'))
exchange.request.header.setContentType('application/json')
CONTINUE
```

`gateway/scripts/commit-response.groovy`:

```groovy
// Replaces GitHub's successful commit response with this API's result:
// status property.successStatus, body property.result (with `commit` filled
// in when present), no body for 204. Errors are left to github-errors.groovy.
import groovy.json.JsonOutput
import groovy.json.JsonSlurper

def res = exchange.response
if (res.statusCode >= 400) return CONTINUE

int status = property.successStatus as int
res.statusCode = status
res.statusMessage = [200: 'OK', 201: 'Created', 204: 'No Content'][status]
if (status == 204) {
    res.setBodyContent(new byte[0])
    return CONTINUE
}

def result = new LinkedHashMap(property.result)
if (result.containsKey('commit')) {
    result.commit = new JsonSlurper().parseText(res.bodyAsStringDecoded).commit?.sha
}
res.setBodyContent(JsonOutput.toJson(result).getBytes('UTF-8'))
res.header.setContentType('application/json')
CONTINUE
```

Append to `gateway/admin.yaml`:

```yaml
---
# PUT /admin/status {text} -> writes src/_data/status.json (creates it if missing)
api:
  name: put-status
  port: 2000
  method: PUT
  path:
    uri: /admin/status
  flow:
    - request:
        - validator:
            jsonSchema: schemas/status.json
        - groovy:
            location: scripts/status-file.groovy
        - call:
            url: "https://api.github.com/repos/Rac0r/mugensame/contents/${property.path}?ref=#{env.GITHUB_BRANCH}"
        - groovy:
            location: scripts/read-sha.groovy
        - groovy:
            location: scripts/commit-body.groovy
    - response:
        - groovy:
            location: scripts/commit-response.groovy
  target:
    method: PUT
    url: "https://api.github.com/repos/Rac0r/mugensame/contents/${property.path}"
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `gateway/test/admin-smoke.sh`
Expected: `0 failed`. A 409 on the second write means `read-sha.groovy` did not find the sha — check that the `call:` URL contains `?ref=` with the test branch.

- [ ] **Step 5: Commit**

```bash
git add gateway/
git commit -m "feat(gateway): status endpoint and shared commit pipeline

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `POST /admin/posts`

**Files:**
- Create: `gateway/scripts/post-file.groovy`, `gateway/schemas/post.json`
- Modify: `gateway/admin.yaml`, `gateway/test/admin-smoke.sh`

**Interfaces:**
- Consumes: commit pipeline from Task 3 (`commit-body.groovy`, `commit-response.groovy`), 422→409 mapping from Task 2.
- Produces: `post-file.groovy`, which serves POST, PUT and DELETE: slug from `title` for POST, from `property.slug` for PUT/DELETE; answers 400 itself for an invalid slug or impossible date; otherwise sets `slug`, `path`, `message`, `successStatus`, `result` and (not for DELETE) `content`. Shell variable `SLUG=gateway-test-hello-1` in `admin-smoke.sh`, used by Task 5.

- [ ] **Step 1: Write the failing tests**

Insert above `# === end of sections ===`:

```bash
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
  "$(sed -n '2,/^---$/p' <<<"$FILE" | sed '$d' | ruby -ryaml -e 'puts YAML.safe_load(STDIN.read, permitted_classes: [Date])["title"]')" \
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
```

(`ruby` ships with macOS; it is used only to prove the front matter parses as YAML.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `gateway/test/admin-smoke.sh`
Expected: create checks FAIL — `POST /admin/posts` has no route (404); the `400` checks fail with 404 too.

- [ ] **Step 3: Implement**

`gateway/schemas/post.json`:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["title", "description", "body"],
  "additionalProperties": false,
  "properties": {
    "title": { "type": "string", "minLength": 1, "maxLength": 200 },
    "description": { "type": "string", "minLength": 1, "maxLength": 500 },
    "body": { "type": "string", "minLength": 1 },
    "tags": {
      "type": "array",
      "uniqueItems": true,
      "items": { "type": "string", "minLength": 1, "maxLength": 50, "pattern": "^[^\\n\\r]+$" }
    },
    "date": { "type": "string", "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}$" },
    "draft": { "type": "boolean" }
  }
}
```

`gateway/scripts/post-file.groovy`:

```groovy
// Prepares a commit of src/posts/<slug>.md for the commit pipeline:
//   POST   /admin/posts         slug derived from the title (same rules as the
//                               site's slugify filter in eleventy.config.js)
//   PUT    /admin/posts/{slug}  slug from the path (property.slug), file replaced
//   DELETE /admin/posts/{slug}  slug from the path, no content
// Answers 400 itself for an unusable slug or an impossible date.
import groovy.json.JsonOutput
import groovy.json.JsonSlurper
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeParseException

String slugify(String s) {
    s.toLowerCase().trim().replaceAll(/[^a-z0-9]+/, '-').replaceAll(/(^-|-$)+/, '')
}

// A JSON string is a valid YAML double-quoted scalar, so this escapes : # " etc.
String yamlString(Object s) {
    JsonOutput.toJson(s.toString())
}

def badRequest = { String message ->
    Response.statusCode(400).contentType('application/json')
            .body(JsonOutput.toJson([error: message])).build()
}

String method = exchange.request.method
def input = method == 'DELETE' ? null : new JsonSlurper().parseText(exchange.request.bodyAsStringDecoded)
String slug = method == 'POST' ? slugify(input.title) : property.slug

if (!(slug ==~ /[a-z0-9]+(-[a-z0-9]+)*/)) {
    return badRequest("No usable slug '${slug}': titles need at least one letter or digit, path slugs look like 'my-post'".toString())
}

property.slug = slug
property.path = "src/posts/${slug}.md".toString()

if (method == 'DELETE') {
    property.message = "admin: delete post ${slug}".toString()
    property.successStatus = 204
    return CONTINUE
}

String date
try {
    date = (input.date ? LocalDate.parse(input.date) : LocalDate.now(ZoneOffset.UTC)).toString()
} catch (DateTimeParseException ignored) {
    return badRequest("Invalid date '${input.date}', expected an existing day as YYYY-MM-DD".toString())
}

def lines = ['---',
             "title: ${yamlString(input.title)}".toString(),
             "description: ${yamlString(input.description)}".toString(),
             "date: ${date}".toString()]
if (input.draft) lines << 'draft: true'
if (input.tags) {
    lines << 'tags:'
    input.tags.each { lines << "  - ${yamlString(it)}".toString() }
}
lines << '---' << '' << input.body.stripTrailing() << ''

property.content = lines.join('\n')
property.message = "admin: ${method == 'POST' ? 'create' : 'update'} post ${slug}".toString()
property.successStatus = method == 'POST' ? 201 : 200
property.result = [slug: slug, path: property.path, commit: null]
CONTINUE
```

Append to `gateway/admin.yaml`:

```yaml
---
# POST /admin/posts {title, description, body, tags?, date?, draft?} -> creates src/posts/<slug>.md
api:
  name: create-post
  port: 2000
  method: POST
  path:
    uri: /admin/posts
  flow:
    - request:
        - validator:
            jsonSchema: schemas/post.json
        - groovy:
            location: scripts/post-file.groovy
        - groovy:
            location: scripts/commit-body.groovy
    - response:
        - groovy:
            location: scripts/commit-response.groovy
  target:
    method: PUT
    url: "https://api.github.com/repos/Rac0r/mugensame/contents/${property.path}"
```

No sha lookup here: creating without `sha` makes GitHub answer 422 for an existing file, which Task 2 maps to 409.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `gateway/test/admin-smoke.sh`
Expected: `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add gateway/
git commit -m "feat(gateway): create posts with validated front matter

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: `PUT` and `DELETE /admin/posts/{slug}`

**Files:**
- Modify: `gateway/admin.yaml`, `gateway/test/admin-smoke.sh`

**Interfaces:**
- Consumes: `post-file.groovy` (reads `property.slug`), `read-sha.groovy`, `commit-body.groovy`, `commit-response.groovy`, `SLUG` and `POST_BODY` from Task 4's test section.
- Produces: nothing new for later tasks.

- [ ] **Step 1: Write the failing tests**

Insert above `# === end of sections ===`:

```bash
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `gateway/test/admin-smoke.sh`
Expected: `update -> 200`, `delete -> 204` and the other status checks FAIL — there is no PUT/DELETE route for `/admin/posts/{slug}` yet. `update did not create file` and `file is gone` may already pass; that is fine.

- [ ] **Step 3: Implement**

Append to `gateway/admin.yaml`:

```yaml
---
# PUT /admin/posts/{slug} -> replaces an existing post; 404 if it does not exist
api:
  name: update-post
  port: 2000
  method: PUT
  path:
    uri: /admin/posts/{slug}
  flow:
    - request:
        - validator:
            jsonSchema: schemas/post.json
        - setProperty:
            name: slug
            value: ${pathParam.slug}
        - groovy:
            location: scripts/post-file.groovy
        - call:
            url: "https://api.github.com/repos/Rac0r/mugensame/contents/${property.path}?ref=#{env.GITHUB_BRANCH}"
        - groovy:
            location: scripts/read-sha.groovy
        - if:
            test: property.sha == null
            flow:
              - static:
                  contentType: application/json
                  src: '{"error": "Not found"}'
              - return:
                  status: 404
        - groovy:
            location: scripts/commit-body.groovy
    - response:
        - groovy:
            location: scripts/commit-response.groovy
  target:
    method: PUT
    url: "https://api.github.com/repos/Rac0r/mugensame/contents/${property.path}"
---
# DELETE /admin/posts/{slug} -> deletes the post; 404 if it does not exist
api:
  name: delete-post
  port: 2000
  method: DELETE
  path:
    uri: /admin/posts/{slug}
  flow:
    - request:
        - setProperty:
            name: slug
            value: ${pathParam.slug}
        - groovy:
            location: scripts/post-file.groovy
        - call:
            url: "https://api.github.com/repos/Rac0r/mugensame/contents/${property.path}?ref=#{env.GITHUB_BRANCH}"
        - groovy:
            location: scripts/read-sha.groovy
        - if:
            test: property.sha == null
            flow:
              - static:
                  contentType: application/json
                  src: '{"error": "Not found"}'
              - return:
                  status: 404
        - groovy:
            location: scripts/commit-body.groovy
    - response:
        - groovy:
            location: scripts/commit-response.groovy
  target:
    method: DELETE
    url: "https://api.github.com/repos/Rac0r/mugensame/contents/${property.path}"
```

The validator runs before `post-file.groovy` reads the body, and `post-file.groovy` runs before the `call:` that overwrites it — keep this order.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `gateway/test/admin-smoke.sh`
Expected: `0 failed`. If `delete -> 204` gets 409 or 422 from GitHub, the DELETE body lacks `sha` — confirm `read-sha.groovy` runs after the `call:`.

- [ ] **Step 5: Commit**

```bash
git add gateway/
git commit -m "feat(gateway): update and delete posts

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: `PUT /admin/images/{filename}`

**Files:**
- Create: `gateway/scripts/image-file.groovy`
- Modify: `gateway/admin.yaml`, `gateway/test/admin-smoke.sh`

**Interfaces:**
- Consumes: `commit-body.groovy` (accepts `byte[]` content), `commit-response.groovy`, 422→409 mapping.
- Produces: images committed to `src/images/<filename>`; result `{url: "/mugensame/images/<filename>"}`. Task 7 makes Eleventy copy that folder.

- [ ] **Step 1: Write the failing tests**

Insert above `# === end of sections ===`:

```bash
# --- images (Task 6)
IMG=$(mktemp); BIG=$(mktemp)
printf '\x89PNG\r\n\x1a\n' > "$IMG"; head -c 2000 /dev/urandom >> "$IMG"
head -c $((5 * 1024 * 1024 + 1)) /dev/urandom > "$BIG"
req PUT /admin/images/smoke-test.png "${KEY[@]}" -H "Content-Type: image/png" --data-binary "@$IMG"
check "image upload -> 201" "$STATUS" 201
check "image url has site prefix" "$(jq -r .url <<<"$BODY")" "/mugensame/images/smoke-test.png"
check "image bytes identical" "$(gh_raw src/images/smoke-test.png | cmp -s - "$IMG" && echo same)" same
req PUT /admin/images/smoke-test.png "${KEY[@]}" -H "Content-Type: image/png" --data-binary "@$IMG"
check "image exists -> 409" "$STATUS" 409
req PUT /admin/images/Bad-Name.PNG "${KEY[@]}" -H "Content-Type: image/png" --data-binary "@$IMG"
check "uppercase filename -> 400" "$STATUS" 400
req PUT /admin/images/notes.txt "${KEY[@]}" -H "Content-Type: text/plain" --data-binary "@$IMG"
check "non-image filename -> 400" "$STATUS" 400
req PUT /admin/images/fake.png "${KEY[@]}" -H "Content-Type: text/plain" --data-binary "@$IMG"
check "non-image content type -> 400" "$STATUS" 400
req PUT /admin/images/big.png "${KEY[@]}" -H "Content-Type: image/png" --data-binary "@$BIG"
check "image over 5 MB -> 413" "$STATUS" 413
check "big image not committed" "$(gh_status src/images/big.png)" 404
rm -f "$IMG" "$BIG"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `gateway/test/admin-smoke.sh`
Expected: image checks FAIL with 404 (no route).

- [ ] **Step 3: Implement**

`gateway/scripts/image-file.groovy`:

```groovy
// PUT /admin/images/{filename}: checks name, type and size, then prepares the
// commit of src/images/<filename>. Creating only - an existing file gives 409.
import groovy.json.JsonOutput

def reject = { int status, String message ->
    Response.statusCode(status).contentType('application/json')
            .body(JsonOutput.toJson([error: message])).build()
}

String name = property.filename
if (!(name ==~ /[a-z0-9][a-z0-9._-]*\.(png|jpe?g|gif|webp|svg)/)) {
    return reject(400, "Invalid filename '${name}': lowercase letters, digits, . _ - and an image extension".toString())
}
String type = exchange.request.header.contentType ?: ''
if (!type.startsWith('image/')) {
    return reject(400, "Content-Type must be image/*, got '${type}'".toString())
}
byte[] bytes = exchange.request.body.content
if (bytes.length == 0) return reject(400, 'Empty image')
if (bytes.length > 5 * 1024 * 1024) return reject(413, 'Image is larger than 5 MB')

property.path = "src/images/${name}".toString()
property.content = bytes
property.message = "admin: add image ${name}".toString()
property.successStatus = 201
property.result = [url: "/mugensame/images/${name}".toString()]
CONTINUE
```

Append to `gateway/admin.yaml`:

```yaml
---
# PUT /admin/images/{filename} (raw image bytes) -> creates src/images/<filename>
api:
  name: upload-image
  port: 2000
  method: PUT
  path:
    uri: /admin/images/{filename}
  flow:
    - request:
        - setProperty:
            name: filename
            value: ${pathParam.filename}
        - groovy:
            location: scripts/image-file.groovy
        - groovy:
            location: scripts/commit-body.groovy
    - response:
        - groovy:
            location: scripts/commit-response.groovy
  target:
    method: PUT
    url: "https://api.github.com/repos/Rac0r/mugensame/contents/${property.path}"
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `gateway/test/admin-smoke.sh`
Expected: `0 failed`. If the oversized upload gets a different status from Membrane itself (a body-size limit firing before the script), stop and report the status and log lines instead of loosening the test — the spec requires 413.

- [ ] **Step 5: Commit**

```bash
git add gateway/
git commit -m "feat(gateway): image uploads

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Site — drafts preprocessor and images passthrough

**Files:**
- Create: `test/site-build.sh`, `src/images/.gitkeep`
- Modify: `eleventy.config.js`

**Interfaces:**
- Consumes: `check`/`finish` from `gateway/test/lib.sh`.
- Produces: `test/site-build.sh` with a `build` function (builds into `$OUT`) and the marker `# === end of sections ===` that Task 9 inserts above.

- [ ] **Step 1: Write the failing test**

`test/site-build.sh`:

```bash
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
```

```bash
chmod +x test/site-build.sh
mkdir -p src/images && touch src/images/.gitkeep
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `test/site-build.sh`
Expected: `draft post is not built` FAILS (`built`), `draft not in feed` FAILS (1), `image copied` FAILS.

- [ ] **Step 3: Implement**

In `eleventy.config.js`, below `eleventyConfig.addPassthroughCopy("src/js");` add:

```js
  eleventyConfig.addPassthroughCopy("src/images");

  // Posts with `draft: true` are left out of production builds (`npm run build`,
  // the deploy workflow) but still render with `npm run serve` for previewing.
  eleventyConfig.addPreprocessor("drafts", "*", (data) => {
    if (data.draft && process.env.ELEVENTY_RUN_MODE === "build") {
      return false;
    }
  });
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `test/site-build.sh`
Expected: `4 passed, 0 failed`; `git status --short` shows no leftover fixture files.

- [ ] **Step 5: Commit**

```bash
git add eleventy.config.js src/images/.gitkeep test/site-build.sh
git commit -m "feat(site): skip drafts in builds and publish src/images

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: `GET /now` aggregator

**Files:**
- Create: `gateway/now.yaml`, `gateway/scripts/now-repos.groovy`, `gateway/scripts/now-posts.groovy`, `gateway/scripts/now-status.groovy`, `gateway/scripts/now-response.groovy`, `gateway/test/now-smoke.sh`

**Interfaces:**
- Consumes: `lib.sh` (`load_env`, `req`, `check`, `start_gateway now`, `stop_gateway`).
- Produces: `GET /now` → 200 `{generatedAt, status: {text, updatedAt} | null, repos: [{name, description, url, pushedAt}] | null, posts: [{title, url, date}] | null}`. Task 9 renders it, Task 10 saves it in CI.

- [ ] **Step 1: Write the failing test**

`gateway/test/now-smoke.sh`:

```bash
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
sleep 1
(export FEED_URL=http://localhost:8765/one.xml; start_gateway now)
req GET /now
check "single-item feed -> one post" "$(jq -r '.posts | length' <<<"$BODY")" 1
check "single-item title" "$(jq -r '.posts[0].title' <<<"$BODY")" "Only post"

finish
```

```bash
chmod +x gateway/test/now-smoke.sh
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `gateway/test/now-smoke.sh`
Expected: exits with "gateway 'now' did not start" (no `now.yaml`).

- [ ] **Step 3: Implement**

`gateway/now.yaml`:

```yaml
# yaml-language-server: $schema=https://www.membrane-api.io/v7.7.0.json
# GET /now - data for the Now page. Read-only. Runs in GitHub Actions
# (gateway/ci-fetch-now.sh) and locally (gateway/run-local.sh now).
# Each `call:` replaces the message body, so every source is reduced to an
# exchange property right after its call; now-response.groovy merges them.
api:
  name: now
  port: 2000
  method: GET
  path:
    uri: /now
  flow:
    - request:
        # 1. Recently pushed repositories
        - setHeader:
            name: Authorization
            value: "Bearer #{env.GITHUB_TOKEN}"
        - setHeader:
            name: Accept
            value: application/vnd.github+json
        - setHeader:
            name: X-GitHub-Api-Version
            value: "2022-11-28"
        - setHeader:
            name: User-Agent
            value: mugensame-gateway
        - call:
            url: https://api.github.com/users/Rac0r/repos?sort=pushed&per_page=5
        - groovy:
            location: scripts/now-repos.groovy
        # 2. Latest posts from the published feed (no token sent to github.io)
        - headerFilter:
            - exclude: authorization
        - call:
            url: "#{env.FEED_URL}"
        - if:
            test: isXML()
            flow:
              - xml2Json: {}
              - groovy:
                  location: scripts/now-posts.groovy
        # 3. Hand-written status, committed by the admin API
        - setHeader:
            name: Authorization
            value: "Bearer #{env.GITHUB_TOKEN}"
        - setHeader:
            name: Accept
            value: application/vnd.github.raw+json
        - call:
            url: https://api.github.com/repos/Rac0r/mugensame/contents/src/_data/status.json
        - groovy:
            location: scripts/now-status.groovy
        - groovy:
            location: scripts/now-response.groovy
```

`gateway/scripts/now-repos.groovy`:

```groovy
// /now step 1: reduces GitHub's repo list to name, description, url, pushedAt.
// property.repos stays null when GitHub answered with an error.
import groovy.json.JsonSlurper

property.repos = null
try {
    def data = new JsonSlurper().parseText(exchange.request.bodyAsStringDecoded)
    if (data instanceof List) {
        property.repos = data.collect { [name: it.name, description: it.description, url: it.html_url, pushedAt: it.pushed_at] }
    }
} catch (ignored) {
}
CONTINUE
```

`gateway/scripts/now-posts.groovy`:

```groovy
// /now step 2 (only runs when the feed was XML, after xml2Json): the three
// newest items. xml2Json turns a single <item> into an object, not a list.
import groovy.json.JsonSlurper

property.posts = null
try {
    def item = new JsonSlurper().parseText(exchange.request.bodyAsStringDecoded)?.rss?.channel?.item
    def items = item == null ? [] : (item instanceof List ? item : [item])
    property.posts = items.take(3).collect { [title: it.title, url: it.link, date: it.pubDate] }
} catch (ignored) {
}
CONTINUE
```

`gateway/scripts/now-status.groovy`:

```groovy
// /now step 3: src/_data/status.json as {text, updatedAt}; null when the file
// does not exist yet (GitHub's 404 JSON has no `text`).
import groovy.json.JsonSlurper

property.status = null
try {
    def s = new JsonSlurper().parseText(exchange.request.bodyAsStringDecoded)
    if (s instanceof Map && s.text instanceof String) {
        property.status = [text: s.text, updatedAt: s.updatedAt]
    }
} catch (ignored) {
}
CONTINUE
```

`gateway/scripts/now-response.groovy`:

```groovy
// /now: merges the three sources into the response. A source that failed is null.
import groovy.json.JsonOutput
import java.time.Instant
import java.time.temporal.ChronoUnit

def now = [generatedAt: Instant.now().truncatedTo(ChronoUnit.SECONDS).toString(),
           status     : property.status,
           repos      : property.repos,
           posts      : property.posts]
Response.ok()
        .contentType('application/json')
        .body(JsonOutput.prettyPrint(JsonOutput.toJson(now)))
        .build()
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `gateway/test/now-smoke.sh`
Expected: `15 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add gateway/now.yaml gateway/scripts/now-*.groovy gateway/test/now-smoke.sh
git commit -m "feat(gateway): /now aggregator

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Now page

**Files:**
- Create: `src/now.njk`
- Modify: `src/_includes/base.njk` (nav), `.gitignore`, `test/site-build.sh`

**Interfaces:**
- Consumes: `/now` JSON shape from Task 8 as Eleventy global data `now` (file `src/_data/now.json`); `build`, `OUT`, `check` from `test/site-build.sh`.
- Produces: page at `/mugensame/now/`; Task 10 writes `src/_data/now.json` before the build.

- [ ] **Step 1: Write the failing tests**

In `test/site-build.sh`, replace the `cleanup()` line (and keep the `trap cleanup EXIT` line after it) with the following, so a real generated `now.json` is backed up and restored:

```bash
NOW_JSON=src/_data/now.json
[ -f "$NOW_JSON" ] && cp "$NOW_JSON" "$OUT.now-backup"
cleanup() {
  rm -rf "$OUT" "${FIXTURES[@]}" "$NOW_JSON"
  [ -f "$OUT.now-backup" ] && mv "$OUT.now-backup" "$NOW_JSON"
}
```

Insert above `# === end of sections ===`:

```bash
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `test/site-build.sh`
Expected: Task 7 checks pass; `now page built` and the other Now checks FAIL.

- [ ] **Step 3: Implement**

`src/now.njk`:

```njk
---
layout: base.njk
title: Now
description: What I'm doing at the moment.
permalink: /now/
---
<section class="prose-page">
  <p class="eyebrow">Current heading</p>
  <h1>Now</h1>

  {% if now.status %}
    <p>{{ now.status.text | escape }}</p>
    <p class="eyebrow">Updated {{ now.status.updatedAt | readableDate }}</p>
  {% else %}
    <p>Status unavailable.</p>
  {% endif %}
</section>

<section class="latest">
  <p class="eyebrow">Recently pushed</p>
  {% if now.repos | length %}
  <div class="post-list">
    {%- for repo in now.repos -%}
    <article class="contact-card">
      <a href="{{ repo.url | escape }}">
        <span class="ping" aria-hidden="true"></span>
        <div>
          <h2>{{ repo.name | escape }}</h2>
          <p class="meta">{{ repo.pushedAt | readableDate }}</p>
          {% if repo.description %}<p class="excerpt">{{ repo.description | escape }}</p>{% endif %}
        </div>
      </a>
    </article>
    {%- endfor -%}
  </div>
  {% else %}
  <p>Repository activity unavailable.</p>
  {% endif %}
</section>

<section class="latest">
  <p class="eyebrow">Latest field notes</p>
  {% if now.posts | length %}
  <div class="post-list">
    {%- for post in now.posts -%}
    <article class="contact-card">
      <a href="{{ post.url | escape }}">
        <span class="ping" aria-hidden="true"></span>
        <div>
          <h2>{{ post.title | escape }}</h2>
          <p class="meta">{{ post.date | readableDate }}</p>
        </div>
      </a>
    </article>
    {%- endfor -%}
  </div>
  {% else %}
  <p>Posts unavailable.</p>
  {% endif %}

  {% if now.generatedAt %}<p class="eyebrow">Collected {{ now.generatedAt | readableDate }}</p>{% endif %}
</section>
```

In `src/_includes/base.njk`, inside `<nav class="site-nav">`, between the Tags and About links:

```njk
      <a href="{{ '/now/' | url }}">Now</a>
```

Append to `.gitignore`:

```
src/_data/now.json
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `test/site-build.sh`
Expected: `0 failed`. Then preview: `npm run serve`, open `http://localhost:8080/mugensame/now/` and check the page looks like the home page's "Latest contacts" cards. Stop the server.

- [ ] **Step 5: Commit**

```bash
git add src/now.njk src/_includes/base.njk .gitignore test/site-build.sh
git commit -m "feat(site): Now page

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: CI — fetch `/now` during the deploy build

**Files:**
- Create: `gateway/ci-fetch-now.sh`, `gateway/test/ci-fetch-now-test.sh`
- Modify: `.github/workflows/deploy.yml`, `gateway/README.md`

**Interfaces:**
- Consumes: `now.yaml` (Task 8), Now page (Task 9), `lib.sh`.
- Produces: `gateway/ci-fetch-now.sh` — runs `now.yaml` in `predic8/membrane:7.7.0` (override with `MEMBRANE_IMAGE`), writes `src/_data/now.json`, always exits 0 and writes `{}` on any failure.

- [ ] **Step 1: Write the failing test**

`gateway/test/ci-fetch-now-test.sh`:

```bash
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
```

```bash
chmod +x gateway/test/ci-fetch-now-test.sh
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `gateway/test/ci-fetch-now-test.sh`
Expected: FAIL — `gateway/ci-fetch-now.sh: No such file or directory`; exit-code checks report 127.

- [ ] **Step 3: Implement the script**

`gateway/ci-fetch-now.sh`:

```bash
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
```

```bash
chmod +x gateway/ci-fetch-now.sh
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `gateway/test/ci-fetch-now-test.sh`
Expected: `6 passed, 0 failed` (the first run pulls the Docker image, allow a minute).

- [ ] **Step 5: Update the workflow**

In `.github/workflows/deploy.yml`:

Add the schedule under `on:` (after `workflow_dispatch:`):

```yaml
    schedule:
        - cron: "17 5 * * *" # daily rebuild so the Now page stays fresh (05:17 UTC)
```

Replace the build job's steps between `- run: npm ci` and `- run: npx @11ty/eleventy` so they read:

```yaml
            - run: npm ci
            - name: Collect Now page data with Membrane
              env:
                GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
              run: gateway/ci-fetch-now.sh
            - run: npx @11ty/eleventy
```

Fix the typo in the deploy job:

```yaml
            url: ${{ steps.deployment.outputs.page_url }}
```

Validate the workflow:

Run: `docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:1.7.7 -color`
Expected: no output, exit 0.

- [ ] **Step 6: Document CI in the README**

Append to `gateway/README.md`:

````markdown
## CI

The deploy workflow runs `gateway/ci-fetch-now.sh` before Eleventy: it starts
`now.yaml` in `predic8/membrane:7.7.0`, saves `GET /now` to `src/_data/now.json`
(git-ignored) and never fails the build — on any error it writes `{}`. A daily
schedule (05:17 UTC) keeps the page fresh. Test it locally with
`gateway/test/ci-fetch-now-test.sh`.
````

- [ ] **Step 7: Run every test once more**

```bash
gateway/test/admin-smoke.sh
gateway/test/now-smoke.sh
test/site-build.sh
gateway/test/ci-fetch-now-test.sh
```

Expected: each ends with `0 failed`.

- [ ] **Step 8: Commit**

```bash
git add gateway/ci-fetch-now.sh gateway/test/ci-fetch-now-test.sh gateway/README.md .github/workflows/deploy.yml
git commit -m "ci: fill the Now page with Membrane during deploy

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 9: Hand over (ask the user; do not push yourself)**

Tell the user the branch is ready and what remains, all of which publish or touch the live site:
1. Push `feat/membrane-gateway` and open a PR (or merge locally) into `main` — merging deploys.
2. After the deploy, run the workflow once by hand (Actions → Deploy to GitHub Pages → Run workflow) and open `https://rac0r.github.io/mugensame/now/`.
3. Set a first status: `gateway/run-local.sh admin`, then `curl -X PUT localhost:2000/admin/status -H "X-Api-Key: $ADMIN_API_KEY" -H 'Content-Type: application/json' -d '{"text":"..."}'`.
