---
id: e02-adaptadores-e-integracoes
titulo: Adaptadores de banco, integrações de API e recursos de ledger e auditoria
status: aberto # aberto · concluido · descartado
abertura: 2026-10-13
canon: ../canon.md
adrs: []
---

# e02-adaptadores-e-integracoes — Adaptadores de banco, integrações de API e recursos de ledger e auditoria

**Objetivo:** ampliar o Enoch além do núcleo do `e01-nucleo-enoch`, com o que foi explicitamente adiado.

**Escopo declarado pelo dono (2026-10-13):** adaptadores MySQL e Postgres; integrações Absinthe e Ash; backup com Litestream; corrente de hashes; excisão; regras recursivas; eventos de transação. Os agregados (D9) e o histórico completo `:history` (D28) foram para o e01; ver `../_sprints/s01-nucleo-enoch/01_grilling/handovers/decisoes.md`.

**Resultado observável:** a definir quando o e01 estiver concluído.

**Fora de escopo:** o núcleo (`e01-nucleo-enoch`) e o domínio financeiro (`e03-obol-sobre-enoch`).

**Perguntas abertas:** ordem interna dos itens, divisão em sprints e critérios de aceite. Serão tratados em um grilling próprio, depois do e01.

## Sprints

Derivadas do campo `epico:` da ficha de cada sprint. Não liste sprints nem o estado delas aqui.

## Notas

A fronteira `Enoch.Storage` do e01 será testada pelos adaptadores deste épico (`../canon/chat.md`, seção "A fronteira do adaptador"). Isso é hipótese do chat, não decisão. Com o motor de consulta único (D6 em `decisoes.md` da s01), o adaptador oferece varreduras de índices, não SQL compilado; o chat descreve o contrário. Com banco de rede, o desempenho das varreduras é um risco deste épico.
