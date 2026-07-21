# Maney

App Rails 8 de orçamento pessoal (single-user). Motor financeiro em
`app/models` + `app/models/budgeting`; specs em `spec/`. Rode testes com
`bin/rspec`.

## Pasta `project/` — SEMPRE visível para o Claude

`/project/` está no `.gitignore` de propósito (workspace de PM, não é
código-fonte), mas **somente o git deve ignorá-la**. Para o Claude ela é
parte integral do workspace:

- Sempre considere `project/` ao explorar, buscar ou listar o repositório.
  Ferramentas de busca que respeitam `.gitignore` (Glob/Grep) vão pulá-la —
  quando a tarefa envolver documentação de produto, liste/busque
  `project/` explicitamente (ex.: `ls project/...`, grep com o caminho).
- Nunca commite nada dentro de `project/`.

## Onde salvar artefatos de PM e de design

Nunca use `docs/` — esse diretório não existe neste repo. Os defaults dos
skills (ex.: `docs/superpowers/specs`, `docs/superpowers/plans`) são
sobrescritos por estes caminhos:

- Epics: `project/pm/epics/`
- Stories/bugs: `project/pm/<decomposição>/` (ex.:
  `project/pm/fechar-o-mes-sem-planilha/`)
- Specs de design (brainstorming): `project/pm/specs/`
- Planos de implementação (writing-plans): `project/pm/plans/`

Convenção de nome: prefixo da wave + tema, sem data — ex.:
`w2-lancamento-manual.md`.
