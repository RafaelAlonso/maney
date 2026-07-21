# Design — W2: Lançamento manual (cartões, categorias, ganhos e gastos)

Story: `project/pm/fechar-o-mes-sem-planilha/w2-story-lancamento-manual.md`
Data: 2026-07-21 · Status: aprovado em brainstorming

## Objetivo

Primeira camada de UI sobre o motor da W1 (já completo e testado): telas
para cadastrar cartões e categorias e lançar ganhos e gastos — incluindo
parcelado no crédito e pagamento de fatura. Toda regra financeira
(atribuição de fatura, divisão de parcelas, saldos, guardas de data) vem do
motor; a UI nunca calcula nem decide fatura/mês.

## Decisões de produto (do brainstorming)

- **Home estrutural do mês** já na W2: linhas (não `<table>`) — linha de
  saldo como placeholder ("—", números reais chegam na W3) e uma linha por
  categoria mostrando o orçado do mês; clique na categoria abre os gastos
  dela naquele mês (todos os métodos). A W3 só preenche números nessa
  estrutura.
- **FAB** (botão flutuante, canto inferior direito) em todas as telas,
  expandindo em duas ações: **gasto** e **ganho**. Nunca obstrui conteúdo
  (padding inferior nas listas).
- **Tailwind CSS** (`tailwindcss-rails`) como base de estilo.
- **Forms como páginas dedicadas** (navegação Turbo padrão), não modais.
- **Setup guiado no primeiro acesso** quando não existe `Setting`.
- Abordagem geral: **REST clássico + Hotwire leve** — controllers REST,
  ERB server-rendered, Stimulus apenas onde há comportamento real.

## Telas e rotas

| Rota | Papel |
|---|---|
| `home#show` (`/`, `?month=YYYY-MM`) | linhas do mês; nav ‹ › limitada para trás pelo primeiro mês, livre para frente |
| `resources :expenses` | lançar/editar/excluir gasto; o mesmo form cria parcelado |
| `resources :incomes` | ganhos do mês; item derivado "saldo do mês anterior" no topo |
| `resources :cards` | CRUD de cartões; edição de dias cria novo `CardSchedule` |
| `card_migrations` (`new`/`create` aninhado em card) | fluxo em lote antes de excluir cartão com gastos |
| `resources :categories` | CRUD + orçado do mês; `show` = gastos da categoria no mês |
| `setup#new/create` | primeiro acesso |
| `settings#edit/update` | primeiro mês, saldo inicial, rename das reservadas |

Navegação global (barra/menu): Ganhos, Gastos, Cartões, Categorias,
Configurações.

## Lançamento de gasto e ganho

**Form de gasto**: nome, valor (BRL "1.234,56" → centavos), data (padrão
hoje), categoria (select; default "outros" quando vazio — AC 12), método
(crédito/débito/dinheiro). Condicionais via Stimulus:

- **cartão** só aparece com método = crédito; sem cartão cadastrado, o
  select dá lugar à mensagem com link para o cadastro (AC 13) — servidor
  valida também.
- **parcelado** (toggle, só no crédito) revela nº de parcelas (mín. 2) e
  parcela inicial (padrão 1); o rótulo do valor vira "valor total".
- O select de categoria esconde "cartão de crédito" quando método =
  crédito (AC 11); validação do motor cobre o servidor.

**Form object `ExpenseEntry`** (ActiveModel): única inteligência nova. No
save decide entre `Expense` avulso e `InstallmentPurchase` (que gera as
parcelas pelo motor). Parcela é identificada por `installment_purchase_id`:

- Editar qualquer parcela abre o form da compra inteira; salvar apaga as
  parcelas e regenera a série (AC 9/10).
- Excluir qualquer parcela confirma e destrói o `InstallmentPurchase`
  (parcelas caem por `dependent: :destroy`).
- Editar data/cartão de gasto avulso no crédito não tem passo extra: a
  fatura é derivada na leitura pelo motor (AC 5/10).

**Form de ganho**: nome, valor, data (padrão hoje). Lista de ganhos mostra
primeiro o derivado "saldo do mês anterior" (motor/BalanceChain), somente
leitura; no primeiro mês é o saldo inicial — "editar" aponta para
configurações, sem excluir (AC 18).

Datas antes do primeiro mês: bloqueio já existe no motor; UI só exibe a
mensagem (AC 19).

## Cartões e categorias

**Cartões**: lista (nome, fechamento, vencimento) com editar/excluir. Form
com nome + dias (1–31; overflow é problema do motor). Edição de dias nunca
altera schedule existente — cria `CardSchedule` novo com vigência a partir
de agora (AC 16 sai do comportamento já provado do motor).

**Exclusão de cartão** com gastos → fluxo em lote (`card_migrations#new`):
tela informa quantos gastos avulsos e compras parceladas existem; opções
*migrar tudo para outro cartão* (select) ou *excluir tudo*. A confirmação
final executa o lote **e exclui o cartão na sequência**. Migrar parcelado =
trocar o cartão da compra. Cartão sem gastos: exclusão direta com
confirmação (AC 17).

**Categorias**: lista com nome + orçado do mês corrente; form grava o
`Budget` do mês em contexto. Reservadas ("outros", "cartão de crédito")
aparecem, são renomeáveis, sem botão de excluir + guarda no servidor
(AC 15). Excluir categoria comum com gastos: confirmação "N gastos serão
movidos para \<padrão\>"; gastos e compras parceladas são reapontados e a
categoria some. Renomear "outros" propaga automaticamente (referência,
AC 12).

## Setup, configurações e erros

- Sem `Setting`: `before_action` global redireciona para `/setup`
  (primeiro mês, padrão = mês atual; saldo inicial). Salvar cria `Setting`
  + categorias reservadas e cai na home.
- Configurações: primeiro mês (motor impede movê-lo para depois de
  lançamentos), saldo inicial, rename das duas reservadas (AC 12).
- Erros de validação renderizam no próprio form (por campo + resumo,
  `status: :unprocessable_entity`); destrutivos sempre com confirmação
  explícita do impacto; flash de sucesso nas ações.

## Testes

Dependências novas: `tailwindcss-rails`; `capybara` +
`selenium-webdriver` (test).

1. **Unidade**: `ExpenseEntry` (avulso vs. parcelado, default "outros",
   parse BRL).
2. **Request specs**: o grosso — cada AC vira pelo menos um exemplo.
3. **System specs (JS)**: só o que depende de browser — FAB, campos
   condicionais, confirmações, redirect de setup.

Meta: as 19 ACs da story cobertas por teste automatizado.

## Fora de escopo (reafirmado)

Números reais na home (saldos, orçado vs. consumo — W3), telas de fatura
(W3), gráficos, auto-categorização, importação, orçado herdado, vínculo
pagamento↔fatura.
