# mugensame

An ocean-themed Eleventy blog: post collections, tags, pagination, and a
depth-gauge scroll effect, ready to deploy to GitHub Pages via GitHub Actions.

## Local development

```bash
npm install
npm run serve
```

Visit `http://localhost:8080`.

## Adding a post

Drop a new Markdown file into `src/posts/`:

```md
---
title: Your Post Title
description: One sentence for the archive and tag list.
date: 2026-06-01
tags:
  - posts
  - some-tag
---

Your content here.
```

Keep the `posts` tag on every post — it's how the `posts` collection is built.
Any other tags you add will automatically get their own page under `/tags/`.

## Before you deploy

Open `eleventy.config.js` and check the `pathPrefix`:

- Deploying to `https://<username>.github.io/<repo-name>/` → set
  `pathPrefix: "/<repo-name>/"` (already set to `/undertow/` — change it to
  match your actual repo name).
- Deploying to `https://<username>.github.io/` (a repo literally named
  `<username>.github.io`) or to a custom domain → remove the `pathPrefix` line
  entirely.

If you're using a custom domain, add a `CNAME` file to `src/` containing your
domain, and add `eleventyConfig.addPassthroughCopy("src/CNAME");` to the config.

## Deploying

1. Push this repo to GitHub.
2. In the repo, go to **Settings → Pages → Build and deployment → Source**,
   and set it to **GitHub Actions**.
3. Push to `main` — the included workflow
   (`.github/workflows/deploy.yml`) builds and deploys automatically.

## Theme notes

Colors and fonts are defined as CSS variables at the top of `src/css/style.css`
if you want to adjust the palette or typography later.