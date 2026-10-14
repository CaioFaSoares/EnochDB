# 02_domain — consolidar decisões e vocabulário

## Objetivo

Dar às decisões confirmadas no grilling uma casa durável, separada do handover que as originou.

## Entradas

- `01_grilling/handovers/decisoes.md` da sprint atual.
- `../../CONTEXT.md` (raiz): termos de domínio já aprovados.
- `../canon.md` e `../adr/`: decisões e numeração existentes.

## Processo

1. Para cada decisão, determine se há trade-off arquitetural que precise de ADR. Uma ADR explica primeiro a dor, registra opções consideradas e fecha a decisão e suas consequências.
2. Numere ADRs em sequência como `NNNN-slug.md`; não altere uma decisão anterior silenciosamente. Uma reversão deve apontar para o registro superado.
3. Acrescente ao glossário somente termos aprovados, com definição e sinônimos que devem ser evitados quando houver.
4. Anote mudanças no canon e aponte para o ADR correspondente; preserve a trilha de decisões superadas.
5. Registre em `handovers/adrs.md` quais decisões e termos foram consolidados e seus caminhos.

## Saída e gate humano

Saída: handover em `docs/_sprints/{sprint}/02_domain/handovers/adrs.md`, ADRs locais e atualizações do glossário. O dono confere se o contexto de cada ADR descreve a dor, não apenas a solução, e aprova a terminologia antes de fechar a etapa.
