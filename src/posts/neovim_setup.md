---
title: A Neovim Setup That Finally Clicked
description: LazyVim, a theme that doesn't fight your eyes, and the plugins worth keeping.
date: 2026-04-02
tags:
  - posts
  - tools
  - neovim
---
I rebuilt my Neovim config more times than I'd like to admit before landing on something that actually stuck. The version that finally worked wasn't the most minimal one — it was the one where every plugin had a specific job and nothing was there "just in case."

LazyVim ended up being the right base: sane defaults, lazy-loading out of the box, and a plugin spec format that's easy to extend without fighting the framework. From there it was mostly subtraction — removing anything that added a keybinding I'd never use on purpose.

The pieces that earned a permanent spot:

- A fuzzy finder fast enough that I stopped thinking about it
- A statusline that shows exactly three things, not twelve
- A theme with enough contrast to read code at midnight without it looking like an alert is going off

The config is still changing, slowly. That's probably the right pace.