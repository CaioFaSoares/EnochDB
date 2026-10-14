# 06_review — revisar antes de entregar

## Objetivo

Verificar a implementação contra os critérios aprovados e os padrões locais antes de preparar uma entrega.

## Entradas

- `05_implement/handovers/implementacao.md` e `04_tickets/handovers/tickets.md`.
- Diff desde a base acordada, canon e ADRs relevantes.

## Processo

1. Revise separadamente conformidade com os padrões locais e atendimento à spec.
2. Para cada achado, registre evidência e escolha: corrigir agora ou abrir item de trabalho; não deixe achado relevante implícito.
3. Resolva divergências com ADR por decisão explícita, não por sobrescrita silenciosa.
4. Escreva `handovers/revisao.md` com achados, correções e itens pendentes.
5. Depois da review, monte `handovers/pr.md` com escopo, itens relacionados, decisões afetadas e comandos de verificação realmente executados.

## Saídas e gate humano

Saídas: `docs/_sprints/{sprint}/06_review/handovers/revisao.md` e `pr.md`. O dono aceita o resultado da review antes de abrir PR; ausência de tracker/host de PR escolhido não autoriza inventar um destino.
