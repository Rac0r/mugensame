# Membrane Site API — Design

Date: 2026-10-13
Status: Draft, awaiting review
Live site: https://rac0r.github.io/mugensame/

## Purpose

Learn the Membrane API Gateway by adding two real features to the mugensame
blog (Eleventy 3, deployed to GitHub Pages by GitHub Actions):

1. **Admin/publishing API** — manage posts, images and a status line from
   scripts or curl, with every change landing as a commit on the repo.
2. **"Now" page** — a page showing recent GitHub activity, the latest posts
   and a hand-written status, aggregated by Membrane.

Learning Membrane is the primary goal. Where a choice trades convenience for
exercising more gateway features, prefer the gateway features, as long as the
result stays usable.

## Decisions

| Topic | Decision |
|---|---|
| Implementation approach | All logic in Membrane YAML flows; Groovy/JS script steps only where YAML cannot do the job (base64 encoding, front-matter assembly) |
| Where Membrane runs | Admin API: locally only. Now aggregator: inside the GitHub Actions build. Same config portable to a host later. |
| Runtime | Locally: native, via `membrane.sh` from the Membrane 7.7.0 distribution at `~/Developer/Tutorials/membrane` (Java 21+; Java 25 installed), wrapped by `gateway/run-local.sh`. In Actions: Docker image `predic8/membrane:7.7.0`. Docker locally only to reproduce CI behaviour. |
| Admin authentication | API key in `X-Api-Key` header (`apiKey:` step). OAuth2 via GitHub is a later, separate lesson. |
| Now page sources | GitHub activity, latest blog posts, hand-written status |
| Config location | `gateway/` folder in this repo |
| Persistence | The repo itself, through the GitHub contents API. No database. |

## Architecture

### Files

```
gateway/
  admin.yaml          # admin API, local only
  now.yaml            # /now aggregator, Actions + local
  scripts/            # Groovy/JS helpers used by script steps
  schemas/            # JSON Schemas for admin request bodies
  test/
    admin-smoke.sh
    now-smoke.sh
  .env.example        # documents required variables
  run-local.sh        # loads .env, starts admin.yaml or now.yaml natively
  README.md           # how to run each part, required tokens
src/_data/status.json # hand-written status, written by the admin API (committed)
src/_data/now.json    # generated during build (git-ignored)
src/images/           # new; passthrough-copied by Eleventy
src/now.njk           # new Now page
```

`admin.yaml` and `now.yaml` are separate so the configuration that runs in CI
contains no write routes and no admin key.

### Configuration and secrets

Provided as environment variables; locally from a git-ignored `gateway/.env`.

| Variable | Used by | Purpose |
|---|---|---|
| `GITHUB_TOKEN` | both | Locally: fine-grained PAT, `contents: write` on `Rac0r/mugensame` only. In Actions: the built-in `GITHUB_TOKEN` (read). |
| `ADMIN_API_KEY` | admin | Secret expected in `X-Api-Key` |
| `GITHUB_BRANCH` | admin | Branch written to. Default `main`; tests use `admin-test`. |
| `FEED_URL` | now | Published RSS feed URL, default `https://rac0r.github.io/mugensame/feed.xml` |

`.gitignore` gains `gateway/.env` and `src/_data/now.json`.

### Running locally

`gateway/run-local.sh <admin|now>` sources `gateway/.env` and runs
`$MEMBRANE_HOME/membrane.sh -c <config>.yaml` from `gateway/`.
`MEMBRANE_HOME` defaults to `~/Developer/Tutorials/membrane` and can be
overridden. The first milestone verifies that relative paths in the configs
(`schemas/`, `scripts/`) resolve correctly when the launcher lives outside
the repo; if they do not, the configs use paths relative to the config file
as Membrane expects, and the script documents it.

### Data flow

- **Admin:** client → `localhost:2000/admin/...` with `X-Api-Key` → Membrane
  checks the key, validates the body, rewrites the request, adds
  `Authorization: Bearer $GITHUB_TOKEN` → GitHub contents API → commit on
  `GITHUB_BRANCH` → (on `main`) existing deploy workflow publishes the site.
- **Now:** Actions build job → Membrane container started in background →
  `curl localhost:2000/now > src/_data/now.json` → container stopped →
  Eleventy builds, exposing the data to templates as `now`.

## Admin API (`gateway/admin.yaml`)

Port 2000. Every route starts with the `apiKey:` step; a missing or wrong key
returns **401**. GitHub base: `https://api.github.com/repos/Rac0r/mugensame/contents/`.

| Route | Request | Behaviour | Success |
|---|---|---|---|
| `GET /admin/posts` | — | List `src/posts/`, keep `*.md` files | 200 `[{slug, sha}]` |
| `GET /admin/posts/{slug}` | — | Fetch `src/posts/{slug}.md` raw | 200 Markdown |
| `POST /admin/posts` | JSON (see below) | Derive slug, build front matter + body, base64, `PUT` without `sha` | 201 `{slug, path, commit}` |
| `PUT /admin/posts/{slug}` | JSON (see below) | `call` GET for `sha`, then `PUT` replacing the whole file | 200 `{slug, path, commit}` |
| `DELETE /admin/posts/{slug}` | — | `call` GET for `sha`, then `DELETE` | 204 |
| `PUT /admin/images/{filename}` | raw bytes, `Content-Type: image/*` | base64, `PUT src/images/{filename}` (create only) | 201 `{url: "/mugensame/images/{filename}"}` |
| `PUT /admin/status` | `{"text": "..."}` | Write `src/_data/status.json` as `{text, updatedAt}`; fetch `sha` first if file exists | 200 `{text, updatedAt}` |

### Post body

```json
{
  "title": "string, required",
  "description": "string, required",
  "tags": ["string"],
  "body": "Markdown string, required",
  "date": "YYYY-MM-DD, optional, defaults to today (UTC)",
  "draft": "boolean, optional, default false"
}
```

Produces a file identical in shape to existing posts:

```markdown
---
title: <title>
description: <description>
date: <date>
draft: true          # only when draft is true
tags:
  - <tag>
---

<body>
```

- **Slug:** derived from `title` with the same rules as the site's `slugify`
  filter (lowercase, non-alphanumerics → `-`, trim leading/trailing `-`).
  `PUT` uses the slug from the path and does not rename files.
- **Validation:** request bodies are validated against JSON Schemas in
  `gateway/schemas/` with Membrane's `validator: { jsonSchema: ... }` step
  (see `examples/validation/json-schema` in the Membrane distribution) before
  any GitHub call; invalid bodies return **400** with the validation messages.
- **Commit messages:** `admin: create post <slug>`, `admin: update post <slug>`,
  `admin: delete post <slug>`, `admin: add image <filename>`, `admin: update status`.
- **Image limits:** filename must match `^[a-z0-9][a-z0-9._-]*\.(png|jpe?g|gif|webp|svg)$`;
  body at most 5 MB, otherwise **413**. The live site is served under
  `/mugensame/` (Eleventy `pathPrefix`), so the returned `url` is
  `/mugensame/images/{filename}` and works when pasted into a post.

### Error mapping

| Situation | Response |
|---|---|
| Missing/invalid API key | 401 |
| Body fails schema / bad filename | 400 |
| Image too large | 413 |
| Create on existing file (GitHub 422) | 409 |
| Update/delete/read of missing file (GitHub 404) | 404 |
| GitHub auth failure (401/403) | 502 with a hint to check `GITHUB_TOKEN` |
| Other GitHub errors | 502 with GitHub's message |

### Drafts

Eleventy 3 does not skip drafts by default. Add a preprocessor in
`eleventy.config.js` that excludes templates with `draft: true` from builds
(the pattern from Eleventy's documentation). Drafts remain visible through
`GET /admin/posts`.

## Now aggregator (`gateway/now.yaml`)

`GET /now` performs three `call`s, stores each result with `setProperty`, and
builds the response with `template`:

1. **Repos:** `GET https://api.github.com/users/Rac0r/repos?sort=pushed&per_page=5`
   → `name`, `description`, `html_url`, `pushed_at`.
2. **Posts:** `GET $FEED_URL` → `xml2Json` → first 3 items → `title`, `link`, `pubDate`.
   Reflects the previously published deploy, since the feed is built in the
   same run.
3. **Status:** `GET contents/src/_data/status.json` (raw) → `text`, `updatedAt`.

Response:

```json
{
  "generatedAt": "ISO-8601",
  "status": { "text": "...", "updatedAt": "ISO-8601" },
  "repos":  [{ "name": "...", "description": "...", "url": "...", "pushedAt": "ISO-8601" }],
  "posts":  [{ "title": "...", "url": "...", "date": "..." }]
}
```

A section whose source fails is `null`; the others are still returned, with
status 200.

## Build and site changes

### `.github/workflows/deploy.yml`

- Build job, after `npm ci`, before Eleventy: start Membrane with `docker run -d`,
  mounting `gateway/` and passing `GITHUB_TOKEN` and `FEED_URL`; poll port 2000
  until it answers (timeout ~60 s); `curl` `/now` into `src/_data/now.json`;
  stop the container.
- If any of that fails, write `{}` to `src/_data/now.json` and continue. The
  Now feature never blocks a deploy.
- Add a daily `schedule:` trigger so the Now page refreshes without commits.
- Fix the existing typo `steps.deloyment` → `steps.deployment`.

### Site

- `eleventy.config.js`: passthrough copy for `src/images`; drafts preprocessor.
- `src/now.njk`: renders `now` in the existing style; shows "unavailable" for
  any `null` or missing section, and when `now` is empty.
- Navigation link to `/now/` in `base.njk` (via the `url` filter, so the prefix is applied).

## Testing

- **Admin:** `gateway/test/admin-smoke.sh` runs against `GITHUB_BRANCH=admin-test`
  (recreated from `main` at the start of each run, deleted at the end) so
  nothing is deployed. Sequence: no key → 401; create → 201; duplicate
  create → 409; invalid body → 400; read; list contains slug; update; image
  upload → 201; status → 200; delete → 204; read deleted → 404. Assertions
  on status codes and key fields via `jq`.
- **Now:** `gateway/test/now-smoke.sh` starts `now.yaml`, checks the response
  shape, then restarts with a broken `FEED_URL` and checks `posts` is `null`
  while `repos` and `status` are present.
- **End to end:** manual `workflow_dispatch` run produces a populated `/now/`
  page on the live site.

## Implementation order

Each milestone works on its own and teaches one main Membrane topic.

1. `GET /admin/posts` + API key — routing, `apiKey`, `call` with auth header
2. `GET /admin/posts/{slug}` — path parameters, request rewriting
3. `PUT /admin/status` — the two-step "fetch `sha`, then write" flow
4. `POST /admin/posts` + schema validation — script step, validation, error mapping
5. `PUT` / `DELETE /admin/posts/{slug}` — reusing the `sha` flow
6. `PUT /admin/images/{filename}` — binary request bodies
7. `/now` locally — orchestration, `xml2Json`, templates
8. Actions integration + `now.njk` — Membrane in Docker on CI

## Out of scope

OAuth2 login (later lesson), web-based editor, partial post edits, renaming
posts, comments, hosting the gateway publicly, multiple authors.
