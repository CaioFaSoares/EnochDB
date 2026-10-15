# ADR-0006 — `:decimal` como inteiro escalado e ordem dos valores definida pelo motor

- **Status:** proposta
- **Data:** 2026-10-15
- **Supera:** —

## Contexto

O e03 depende de somar saldos sem perder precisão, e o pushdown de `v` (ver [ADR-0001](0001-avaliador-datalog-unico-em-elixir.md)) só funciona se a ordem dos valores for a mesma no SQLite e no `Memory`. Ponto flutuante perde precisão. Deixar a ordem a cargo do banco (afinidade da coluna do SQLite) ou da ordem de termos do Erlang daria resultados diferentes por adaptador.

Há também uma dor de segurança: o `decimal` 2.4.1 tem dois avisos de `mix hex.audit` (EEF-CVE-2026-32686, expoente sem limite na entrada, e EEF-CVE-2026-97853, alocação sem limite em `Decimal.round/3`), e valores `Decimal` chegam de entrada externa.

## Decisão

- `:decimal` é um inteiro escalado, com a escala fixa por atributo e declarada no schema (`scale: 2` grava `1050` para `10,50`). O inteiro tem 64 bits; estouro é erro explícito, nunca truncamento. O tipo não conhece moeda.
- Mais casas que a escala é rejeitado com erro explícito; menos casas é aceito e normalizado. O framework não arredonda.
- Na API, `:decimal` é a struct `Decimal`, com `decimal ~> 3.2`. O Enoch nunca chama `Decimal.round/3` e, na fronteira, antes de qualquer aritmética, confere o expoente e o número de dígitos do coeficiente contra a escala do atributo e o limite de 64 bits, o que bloqueia valores como `1e999999999`.
- Tipos do e01: `:string`, `:long`, `:boolean`, `:ref`, `:keyword`, `:uuid`, `:instant` e `:decimal`. Sem `:double`, `:bytes` nem `:uri`.
- A ordem em cada tipo é definida pelo motor: numérica para `:long`, `:decimal` e `:instant`; bytes de UTF-8 para `:string` e `:keyword`; `false` antes de `true`; os 16 bytes sem sinal para `:uuid`; o id inteiro para `:ref`. `:instant` são microssegundos desde a época; a unidade exata fica para a spec.
- Cada atributo tem um único tipo, e os literais de consulta são interpretados pelo tipo do atributo a que a variável está ligada.
- A mistura numérica (`:long` com `:decimal`, e `:decimal` de escalas diferentes) é exata em ordem, igualdade e junção: o motor leva os dois lados à mesma escala antes de comparar. Qualquer outra comparação de ordem entre tipos diferentes é erro. Igualdade e junção entre tipos não numéricos diferentes não casam, sem erro. Um literal de ponto flutuante contra um `:decimal` é erro.

## Opções consideradas

- **Inteiro escalado:** preserva a ordem, então o pushdown de `v` continua válido, e os agregados somam inteiros.
- **Ponto flutuante:** fora do e01; não há `:double`.
- **Ordem herdada do banco ou dos termos do Erlang:** rejeitada; a ordem é do motor para ser igual nos dois adaptadores.

## Consequências

- O limite de 64 bits e a escala por atributo já impõem um teto ao que é gravado.
- A regra de que igualdade e junção entre tipos não numéricos diferentes não casam, sem erro, é iniciativa do agente, aceita junto com o conjunto no gate do `01_grilling`.
- A spec fixa a unidade exata de `:instant`.
- A suíte de contrato cobre ordem e normalização do `:decimal` nos dois adaptadores (D17, critério 1).

## Referências

- Decisões D12, D13, D36, D37, D38 e itens 16, 17, 20, 39 em [`decisoes.md`](../_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md).
- Contagem de tipos no Tickety: `_work/_Copland/Tickety/server/src/ticketeria/db/schema.clj`, citada na D36.
