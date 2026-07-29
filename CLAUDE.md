# Maney

A Rails 8 personal-budgeting app (single-user). The financial engine lives in
`app/models` + `app/models/budgeting`; specs in `spec/`. Run the tests with
`bin/rspec`.

## Language policy

Everything a developer reads is in English: code, identifiers, comments, test
descriptions, and all documentation (this file and `project/`). Only text a
user sees stays in Portuguese: view copy, flash messages, validation messages,
UI labels, seeded category names, and any spec assertion that matches those
strings.

## The `project/` folder — ALWAYS visible to Claude

`/project/` is in `.gitignore` on purpose (a PM workspace, not source code),
but **only git should ignore it**. For Claude it is an integral part of the
workspace:

- Always consider `project/` when exploring, searching, or listing the repo.
  Search tools that respect `.gitignore` (Glob/Grep) will skip it — when the
  task involves product documentation, list/search `project/` explicitly
  (e.g. `ls project/...`, grep with the path).
- Never commit anything inside `project/`.

## Where to save PM and design artifacts

Never use `docs/` — that directory does not exist in this repo. The skills'
defaults (e.g. `docs/superpowers/specs`, `docs/superpowers/plans`) are
overridden by these paths:

**One epic, one folder.** Everything about an epic lives in
`project/pm/<YYYY-MM-DD>-<epic-slug>/`, dated when the epic is written:

```
project/pm/2026-07-29-seeing-the-money-without-doing-the-math/
  EPIC.md                                    # the epic (pm-epic)
  index.md                                   # indexes every file here (pm-decomposition)
  stories/w1-story-cash-forecast-balance.md  # stories (pm-stories)
  specs/w1-cash-forecast-balance.md          # design specs (brainstorming)
  plans/w1-cash-forecast-balance.md          # implementation plans (writing-plans)
```

- The epic folder is created by `pm-epic`, when `EPIC.md` is written — not by
  `pm-decomposition`. Stories are filed into the existing folder.
- `index.md` covers everything in the folder, `EPIC.md` included, and names each
  story's spec and plan (or says they are not written yet).
- Stories, specs and plans each get their own subfolder; only `EPIC.md` and
  `index.md` sit at the top, so the folder root always reads as the entry point.
- Every file keeps its wave prefix, no date — e.g. `w2-manual-entry.md`. Without
  the per-epic folder, waves from different epics collide (both current epics
  have a `w1-`).
- Bugs are not epic-scoped and stay flat in `project/pm/bugs/`.
