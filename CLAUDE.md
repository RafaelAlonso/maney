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

- Epics: `project/pm/epics/`
- Stories/bugs: `project/pm/<decomposition>/` (e.g.
  `project/pm/closing-the-month-without-a-spreadsheet/`)
- Design specs (brainstorming): `project/pm/specs/`
- Implementation plans (writing-plans): `project/pm/plans/`

Naming convention: wave prefix + theme, no date — e.g.
`w2-manual-entry.md`.
