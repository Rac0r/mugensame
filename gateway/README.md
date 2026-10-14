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

Listens on 127.0.0.1 only. Every request needs `X-Api-Key: <ADMIN_API_KEY>` (missing → 401, wrong → 403). Every write is one commit on
`GITHUB_BRANCH` (default `main`, which deploys the site).

| Request | Body | Result |
|---|---|---|
| `GET /admin/posts` | — | `[{slug, sha}]` |
| `GET /admin/posts/{slug}` | — | Markdown |
| `POST /admin/posts` | `{title, description, body, tags?, date?, draft?}` | 201 `{slug, path, commit}` |
| `PUT /admin/posts/{slug}` | same as POST, but `date` and `draft` are required (the whole file is replaced) | 200 `{slug, path, commit}` |
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
gateway/test/ci-fetch-now-test.sh  # the CI step, in Docker
```

## CI

The deploy workflow runs `gateway/ci-fetch-now.sh` before Eleventy: it starts
`now.yaml` in `predic8/membrane:7.7.0`, saves `GET /now` to `src/_data/now.json`
(git-ignored) and never fails the build — on any error it writes `{}`. A daily
schedule (05:17 UTC) keeps the page fresh. Test it locally with
`gateway/test/ci-fetch-now-test.sh`.
