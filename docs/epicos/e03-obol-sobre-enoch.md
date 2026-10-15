---
id: e03-obol-sobre-enoch
titulo: Refazer o Obol usando o Enoch como banco, API e ledger
status: aberto # aberto · concluido · descartado
abertura: 2026-10-13
canon: ../canon.md
adrs: []
---

# e03-obol-sobre-enoch — Refazer o Obol usando o Enoch como banco, API e ledger

**Objetivo:** remontar o Obol, projeto existente de organização financeira em `_Mine/Obol`, com o Enoch como base de dados, API e backend de ledger.

**Resultado observável:** a definir quando os épicos anteriores estiverem concluídos.

**Fora de escopo:** o desenvolvimento do próprio Enoch (`e01-nucleo-enoch`, `e02-adaptadores-e-integracoes`).

**Perguntas abertas:**
- Quais funcionalidades do Obol atual entram na reescrita. O README do Obol descreve faturas de cartão, orçamentos por categoria e projeção de fluxo de caixa.
- Se o front-end do Obol (Nuxt) permanece. Hoje o Obol usa Nuxt, ElysiaJS/Bun e PocketBase.
- Quais necessidades do ledger sobem para o framework e quais ficam no app. A regra proposta no chat ainda não foi decidida.
- Como o ledger estende o núcleo do Enoch para a moeda e demais regras de domínio. O dono decidiu (D12 em `decisoes.md` da s01) que o `:decimal` do framework não conhece moeda e que isso entra no e03 como extensão ao núcleo. O mecanismo de extensão não foi definido.

## Sprints

Derivadas do campo `epico:` da ficha de cada sprint. Não liste sprints nem o estado delas aqui.

## Notas

O chat (`../canon/chat.md`) chama o cliente de `Thoth`. O dono decidiu usar o nome e o projeto Obol.
